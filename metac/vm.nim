import os, reactor, caprpc, metac/instance, metac/schemas, collections, posix, reactor/process
import metac/stream

type
  VMServiceImpl = ref object of RootObj
    instance: Instance

  VMLauncherImpl = ref object of RootObj
    service: VMServiceImpl

  VMImpl = ref object of RootObj
    service: VMServiceImpl
    process: Process

proc getMachineType(info: MachineInfo): string =
  var s: string
  case info.`type`:
    of MachineInfo_Type.kvm64: s = "kvm64"
    of MachineInfo_Type.host: s = "host"

  if info.hideVm:
    s &= ",kvm=off"

  return s

proc qemuQuoteName(v: string): string =
  # TODO
  if v == nil:
    return ""
  for ch in v:
    if ch in {';', ':', ',', '\0', '\L'}:
      raise newException(ValueError, "invalid name")
  return v

proc launch(self: VMLauncherImpl, config: LaunchConfiguration): Future[VM] {.async.} =
  let vm = VMImpl(service: self.service)
  var cmdline = @["qemu-system-x86_64",
                  "-enable-kvm",
                  "-nographic",
                  "-nodefaults",
                  "-sandbox", "on"]

  echo "launch vm: ", config.pprint
  var fds: seq[cint] = @[]

  proc cleanupFds() =
    for fd in fds:
      discard close(fd)

  # TODO: defer
  # defer: cleanupFds(fds)

  if config.boot.kind == LaunchConfiguration_BootKind.disk:
    if config.boot.disk != 0:
      asyncRaise("can only boot from the first hard disk")
    cmdline &= ["-boot", "c"]
  elif config.boot.kind == LaunchConfiguration_BootKind.kernel:
    cmdline &= []
  else:
    asyncRaise("unsupported boot method")

  # memory
  cmdline &= ["-m", $config.memory]

  # vcpu
  cmdline &= ["-vcpu", $config.vcpu]

  # machineInfo
  cmdline &= ["-M", getMachineType(config.machineInfo)]

  # networks

  # drives

  # serialPorts
  for i, serialPort in config.serialPorts:
    let (sockFd, holder) = await unwrapStream(self.service.instance,
                                              serialPort.stream)
    fds.add sockFd
    cmdline &= [
      "-add-fd", "fd=$1,set=$2" % [$sockFd, $sockFd],
      "-chardev", "serial,id=serial$1,path=/dev/fdset/$2" % [$i, $sockFd]
    ]

    if serialPort.driver == SerialPort_Driver.virtio:
      cmdline &= [
        "-device", "virtserialport,chardev=serial$1,name=$2" % [$i, qemuQuoteName(serialPort.name)]]
    else:
      cmdline &= ["-device", "chardev:serial%d" % [$i]]

  # pciDevices

  echo("starting QEMU ", cmdline)

  vm.process = startProcess(cmdline)

proc getPinnedVMs(self: VMServiceImpl): Future[seq[VM]] {.async.} =
  return nil

proc getPciDevices(self: VMServiceImpl): Future[seq[PciDevice]] {.async.} =
  return nil

proc toCapServer(self: VMLauncherImpl): CapServer =
  return toGenericCapServer(self.asVMLauncher)

proc getLauncher(self: VMServiceImpl): Future[VMLauncher] {.async.} =
  return VMLauncherImpl(service: self).asVMLauncher

proc toCapServer(self: VMServiceImpl): CapServer =
  return toGenericCapServer(self.asVMServiceAdmin)

proc main() {.async.} =
  let instance = await newInstance(paramStr(1))

  let serviceAdmin = VMServiceImpl(instance: instance).asVMServiceAdmin

  let holder = await instance.thisNodeAdmin.registerNamedService(
    name="vm",
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=ServiceAdmin.createFromCap(serviceAdmin.toCapServer)
  )
  await waitForever()

when isMainModule:
  main().runMain()
