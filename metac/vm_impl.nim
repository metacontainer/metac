import xrest, metac/vm, metac/fs, strutils, metac/service_common, metac/rest_common, metac/os_fs, posix, reactor/unix, reactor/process, options, metac/util, collections

{.reorder: on.}

type
  VMImpl = ref object
    id: string
    cleanupProcs: seq[proc()]
    vncPath: string
    config: VM
    process: process.Process

  VMService = ref object
    vms: Table[string, VMImpl]

proc get(): seq[VMRef] =
  discard

proc create(self: VMService, config: VM): Future[VMRef] {.async.} =
  let vm = await launchVm(config)
  self.vms[vm.id] = vm
  return makeRef(VMRef, "./" & vm.id)

proc item(self: VMService, id: string): VMImpl =
  return self.vms[id]

proc delete(self: VMImpl) =
  discard

proc qemuQuoteName(v: string): string =
  # TODO
  for ch in v:
    if ch in {';', ':', ',', '\0', '\L'}:
      raise newException(ValueError, "invalid name")
  return v

proc launchVm(config: VM): Future[VMImpl] {.async.} =
  var vm: VMImpl
  vm.id = hexUrandom()

  var cmdline = @["qemu-system-x86_64",
                  "-enable-kvm",
                  "-nographic",
                  "-nodefaults",
                  "-device", "virtio-balloon", # automatic=true
                  #"-sandbox", "on"
  ]
  var env = @[("QEMU_AUDIO_DRV", "spice")]
  var fds: seq[cint] = @[]

  defer:
    for fd in fds:
      discard close(fd)


  if config.bootDisk.isSome:
    let diskId = config.bootDisk.get
    if diskId != 0:
      raise newException(Exception, "can only boot from the first hard disk")
    cmdline &= ["-boot", "c"]

  elif config.bootKernel.isSome:
    let bootOpt = config.bootKernel.get

    let (kernelFile, cleanup1) = await copyToTemp(bootOpt.kernel)
    vm.cleanupProcs.add cleanup1
    cmdline &= [
      "-kernel", kernelFile,
      "-append", bootOpt.cmdline]

    if bootOpt.initrd.isSome:
      let (initrdFile, cleanup2) = await copyToTemp(bootOpt.initrd.get)
      cmdline &= ["-initrd", initrdFile]
      vm.cleanupProcs.add cleanup2
  else:
    raise newException(Exception, "missing boot field")

  # rng
  cmdline &= ["-device", "virtio-rng-pci"]

  # memory
  cmdline &= ["-m", $config.memory]

  # vcpu
  cmdline &= ["-smp", $config.vcpu]

  # machineInfo
  # cmdline &= getMachineType(config.machineInfo)

  # display
  cmdline &= ["-vga", "qxl"]
  block vnc:
    let (path, cleanup) = createUnixSocketDir()
    cmdline &= ["-vnc", "unix:" & path & ",lossy"]
    vm.vncPath = path
    vm.cleanupProcs.add cleanup

  cmdline &= ["-soundhw", "hda"]

  block spice:
    # https://www.spice-space.org/spice-user-manual.html#_video_compression
    let (path, cleanup) = createUnixSocketDir()
    cmdline &= ["-spice", "unix,disable-ticketing,addr=" & path] # streaming-video=filter
    # gl=on needed with -device virtio-vga,virgl=on

    cmdline &= ["-device", "virtio-serial",
                "-chardev", "spicevmc,id=vdagent,debug=0,name=vdagent",
                "-device", "virtserialport,chardev=vdagent,name=com.redhat.spice.0"]

  # drives
  for i, drive in config.drives:
    let nbdStream = await drive.device.nbdConnection()
    let (nbdPath, cleanup) = makeUnixSocket(nbdStream)
    cmdline &= [
      "-drive", "format=raw,file=nbd:unix:" & nbdPath
    ]
    vm.cleanupProcs.add cleanup

  var serialPortPaths: seq[string] = @[]

  # serialPorts
  for i, serialPort in config.serialPorts:
    let (dirPath, cleanup) = createUnixSocketDir()
    let path = dirPath & "/socket"
    cmdline &= [
      "-chardev", "socket,id=metacserial$1,path=$2,server$3" % [$i, $path, if serialPort.nowait: ",nowait" else: ""]
    ]
    vm.cleanupProcs.add cleanup
    serialPortPaths.add path

    if serialPort.driver == SerialPort_Driver.virtio:
      cmdline &= [
        "-device", "virtio-serial",
        "-device", "virtserialport,chardev=metacserial$1,name=$2" % [$i, qemuQuoteName(serialPort.name)]
      ]
    else:
      cmdline &= ["-device", "isa-serial,chardev=metacserial$1" % [$i]]

  # pciDevices

  var additionalFiles = @[(1.cint, 1.cint), (2.cint, 2.cint)]
  for fd in fds:
    setBlocking(fd)
    additionalFiles.add((fd, fd))

  vm.process = startProcess(cmdline, additionalFiles = additionalFiles)

  return vm
