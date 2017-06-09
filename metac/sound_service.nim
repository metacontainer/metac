import os, reactor, caprpc, metac/instance, metac/schemas, collections, reactor/process, reactor/file, metac/process_util, osproc, posix
import metac/stream, metac/persistence
import metac/sound_schema

type
  SoundServiceAdminImpl = ref object of RootObj
    instance: ServiceInstance
    systemMixer: MixerImpl
    systemMixerMutex: AsyncMutex

  MixerImpl = ref object of RootObj
    instance: ServiceInstance
    socketPath: string

  SoundDeviceImpl = ref object of RootObj
    # either a sink or a source
    mixer: MixerImpl
    isSink: bool
    name: string

proc info(self: SoundDeviceImpl): Future[SoundDeviceInfo] {.async.} =
  return SoundDeviceInfo(name: self.name,
                         isSink: self.isSink,
                         isHardware: self.name.startswith("alsa_"))

proc opusStream(self: SoundDeviceImpl): Future[Stream] {.async.} =
  # be somehow more intelligent about format and OPUS parameters
  # (and use RTP in future)
  let opts = "--file-format=wav -d $1" % [quoteShell(self.name)]
  var cmd: string
  if self.isSink:
    cmd = "opusdec --force-wav - - | paplay $1" % [opts]
  else:
    cmd = "parec --channels=2 --format=s16le --rate=44100 $1 | opusenc --max-delay 100 --raw --raw-bits 16 --raw-rate 44100 --raw-chan 2 - -" % [opts]

  let pFd: cint = if self.isSink: 0 else: 1
  let process = startProcess(@["sh", "-c", cmd],
                             additionalFiles = @[(2.cint, 2.cint)],
                             additionalEnv = @[("PULSE_SERVER", "unix:" & self.mixer.socketPath)],
                             pipeFiles= @[pFd])
  return self.mixer.instance.wrapStream(process.files[0])

proc bindTo(self: SoundDeviceImpl, other: SoundDevice): Future[Holder] {.async.} =
  let selfStream = await other.opusStream
  let otherStream = await self.opusStream
  return selfStream.bindTo(otherStream)

capServerImpl(SoundDeviceImpl, [SoundDevice])

proc createDevice(self: MixerImpl, name: string, sink: bool): Future[SoundDevice] {.async.} =
  let name = "metac." & hexUrandom(5) & "." & name
  let sinkOrSource = if sink: "sink" else: "source"
  await execCmd(@["pactl", "--server=" & self.socketPath, "load-module", "null-" & sinkOrSource, sinkOrSource & "_name=" & name])
  let monitorName = name & ".monitor"

  return SoundDeviceImpl(mixer: self, isSink: not sink, name: monitorName).asSoundDevice

proc createSink(self: MixerImpl, name: string): Future[SoundDevice] {.async.} =
  return createDevice(self, name, sink=true)

proc createSource(self: MixerImpl, name: string): Future[SoundDevice] {.async.} =
  # TODO: this doesn't work, because sources don't have monitors
  return createDevice(self, name, sink=false)

proc getSink(self: MixerImpl, name: string): Future[SoundDevice] {.async.} =
  return SoundDeviceImpl(mixer: self, isSink: true, name: name).asSoundDevice

proc getSource(self: MixerImpl, name: string): Future[SoundDevice] {.async.} =
  return SoundDeviceImpl(mixer: self, isSink: false, name: name).asSoundDevice

proc getDevices(self: MixerImpl): Future[seq[SoundDevice]] {.async.} =
  await execCmd(@["pactl", "--server=" & self.socketPath, "list"])
  return @[] # TODO

capServerImpl(MixerImpl, [Mixer])

proc mkdtemp(tmpl: cstring): cstring {.importc, header: "stdlib.h".}

proc getSystemMixer(self: SoundServiceAdminImpl): Future[Mixer] {.async.} =
  await self.systemMixerMutex.lock
  defer: self.systemMixerMutex.unlock

  if self.systemMixer == nil:
    let mixer = MixerImpl(instance: self.instance)

    var dirPath = "/tmp/metac_pulse_XXXXXXXX"
    if mkdtemp(dirPath) == nil:
      raiseOSError(osLastError())
    await execCmd(@["chown", "pulse:root", dirPath])
    await execCmd(@["chmod", "770", dirPath])

    mixer.socketPath = dirPath & "/socket"
    echo "spawning PulseAudio..."
    let process =
      startProcess(@["pulseaudio",
                     "--system", "-n",
                     "--disallow-exit", "--use-pid-file=false",
                     "--load=module-always-sink",
                     "--load=module-rescue-streams",
                     "--load=module-suspend-on-idle",
                     "--load=module-udev-detect",
                     "--load=module-native-protocol-unix auth-anonymous=1 socket=" & mixer.socketPath],
                   additionalEnv = @[("DBUS_SYSTEM_BUS_ADDRESS", "none")],
                   additionalFiles = [(1.cint, 1.cint), (2.cint, 2.cint)])
    await waitForFile(mixer.socketPath)
    echo "PulseAudio started"

    self.systemMixer = mixer
    discard process

  return self.systemMixer.asMixer

capServerImpl(SoundServiceAdminImpl, [SoundServiceAdmin])

proc main*() {.async.} =
  let instance = await newServiceInstance("sound")

  let serviceImpl = SoundServiceAdminImpl(instance: instance, systemMixerMutex: newAsyncMutex())
  let serviceAdmin = serviceImpl.asSoundServiceAdmin

  await instance.registerRestorer(
    proc(d: CapDescription): Future[AnyPointer] =
      case d.category:
      else:
        return error(AnyPointer, "unknown category"))

  await instance.runService(
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=serviceAdmin.castAs(ServiceAdmin)
  )

when isMainModule:
  main().runMain()
