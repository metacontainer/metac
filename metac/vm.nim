import os, reactor, caprpc, metac/instance, metac/schemas, collections, posix, reactor/process, reactor/file, metac/process_util
import metac/stream, metac/fs, metac/persistence

type
  VMServiceImpl = ref object of RootObj
    instance: ServiceInstance

  VMImpl = ref object of PersistableObj
    instance: ServiceInstance
    process: process.Process
    cleanupProcs: seq[proc()]
    holders: seq[Holder]

    serialPorts: seq[Stream]
    networks: seq[L2Interface]

proc getMachineType(info: MachineInfo): seq[string] =
  var s: string
  case info.`type`:
    of MachineInfo_Type.kvm64: s = "kvm64"
    of MachineInfo_Type.host: s = "host"

  if info.hideVm:
    s &= ",kvm=off"

  return @["-M", "pc-i440fx-2.5", "-cpu", s]

proc qemuQuoteName(v: string): string =
  # TODO
  if v == nil:
    return ""
  for ch in v:
    if ch in {';', ':', ',', '\0', '\L'}:
      raise newException(ValueError, "invalid name")
  return v

proc network(self: VMImpl, index: int32): Future[L2Interface] {.async.}
proc serialPort(self: VMImpl, index: int32): Future[Stream] {.async.}
proc stop(self: VMImpl): Future[void] {.async.}
proc destroy(self: VMImpl): Future[void] {.async.}

capServerImpl(VMImpl, [VM, Persistable, Waitable])

proc stop(self: VMImpl): Future[void] {.async.} =
  discard

proc serialPort(self: VMImpl, index: int32): Future[Stream] {.async.} =
  if index < 0 or index >= self.serialPorts.len:
    return error(Stream, "VM.serialPort: bad index")

  let sock =
    injectPersistence(
      self.serialPorts[index.int],
      makePersistenceCallDelegate(self.instance, self.asVM, VM_serialPort_Params(index: index)))
  return sock

proc network(self: VMImpl, index: int32): Future[L2Interface] {.async.} =
  if index < 0 or index >= self.networks.len:
    return error(L2Interface, "VM.network: bad index")
  return self.networks[index.int]

proc destroyVM(self: VMImpl) =
  echo "VM: destroy"
  self.process.kill()

proc destroy(self: VMImpl): Future[void] {.async.} =
  destroyVM(self)

proc launchVM(instance: ServiceInstance, config: LaunchConfiguration, persistenceDelegate: PersistenceDelegate=nil): Future[VM] {.async.} =
  var vm: VMImpl
  new(vm, destroyVM)
  vm.instance = instance
  vm.cleanupProcs = @[]
  vm.serialPorts = @[]
  vm.networks = @[]
  vm.persistenceDelegate = persistenceDelegate
  vm.holders = @[]

  var cmdline = @["qemu-system-x86_64",
                  "-enable-kvm",
                  "-nographic",
                  "-nodefaults",
                  #"-sandbox", "on"
  ]

  var fds: seq[cint] = @[]

  defer:
    for fd in fds:
      discard close(fd)

  if config.boot.kind == LaunchConfiguration_BootKind.disk:
    if config.boot.disk != 0:
      asyncRaise("can only boot from the first hard disk")
    cmdline &= ["-boot", "c"]
  elif config.boot.kind == LaunchConfiguration_BootKind.kernel and config.boot.kernel != nil:
    let bootOpt = config.boot.kernel

    proc copyToTemp(f: schemas.File): Future[string] {.async.} =
      var path = await copyToTempFile(instance, f)
      let fd = posix.open(path, O_RDONLY)
      fds.add fd
      removeFile path
      return "/proc/self/fd/" & $fd

    let kernelFile = await copyToTemp(bootOpt.kernel)
    cmdline &= [
      "-kernel", kernelFile,
      "-append", bootOpt.cmdline]
    if not bootOpt.initrd.toCapServer.isNullCap:
      let initrdFile = await copyToTemp(bootOpt.initrd)
      cmdline &= ["-initrd", initrdFile]
  else:
    asyncRaise("unsupported boot method")

  # rng
  cmdline &= ["-device", "virtio-rng-pci"]

  # memory
  cmdline &= ["-m", $config.memory]

  # vcpu
  cmdline &= ["-smp", $config.vcpu]

  # machineInfo
  cmdline &= getMachineType(config.machineInfo)

  let networkAdmin = instance.getServiceAdmin("network", NetworkServiceAdmin)

  # networks
  for i, network in config.networks:
    let tapName = "mcvm" & hexUrandom(5)
    let driver = case network.driver:
                   of Network_Driver.e1000: "e1000"
                   of Network_Driver.virtio: "virtio-net-pci"

    await execCmd(@["ip", "tuntap", "add", "dev", tapName, "mode", "tap"])

    # TODO(perf): vhost=on
    cmdline &= ["-netdev", "tap,ifname=$1,script=no,downscript=no,id=metacnet$2" % [tapName, $i]]
    cmdline &= ["-device", "$1,netdev=metacnet$2" % [driver, $i]]

    let theDevice = await networkAdmin.rootNamespace.getInterface(tapName).l2interface

    if network.network.toCapServer.isNullCap:
      vm.networks.add theDevice
    else:
      let holder = await theDevice.bindTo(network.network)
      vm.holders.add(holder)
      vm.networks.add network.network

  # drives
  for i, drive in config.drives:
    let nbdStream = await drive.device.nbdSetup()
    let nbdPath = await unwrapStreamToUnixSocket(instance, nbdStream)
    cmdline &= [
      "-drive", "format=raw,file=nbd:unix:" & nbdPath
    ]

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

  echo("starting QEMU ", cmdline.join(" "))

  var additionalFiles = @[(1.cint, 1.cint), (2.cint, 2.cint)]
  for fd in fds:
    setBlocking(fd)
    additionalFiles.add((fd, fd))

  vm.process = startProcess(cmdline, additionalFiles= additionalFiles)

  for i, path in serialPortPaths:
    await waitForFile(path)
    let sock = instance.wrapUnixSocketAsStream(path)
    vm.serialPorts.add sock

  echo "VM refcnt:", getRefcount(vm)

  return vm.asVM

proc launch(self: VMServiceImpl, config: LaunchConfiguration, runtimeId: string=nil): Future[VM] {.async.} =
  return launchVM(self.instance, config,
                  self.instance.makePersistenceDelegate("vm:vm", description=config.toAnyPointer, runtimeId=runtimeId))

proc getPinnedVMs(self: VMServiceImpl): Future[seq[VM]] {.async.} =
  return nil

proc getPciDevices(self: VMServiceImpl): Future[seq[PciDevice]] {.async.} =
  return nil

proc getLauncher(self: VMServiceImpl): Future[VMLauncher] {.async.}

capServerImpl(VMServiceImpl, [VMLauncher, VMServiceAdmin])

proc getLauncher(self: VMServiceImpl): Future[VMLauncher] {.async.} =
  return self.restrictInterfaces(VMLauncher)

proc main*() {.async.} =
  enableGcNoDelay()
  let instance = await newServiceInstance("vm")

  let serviceImpl = VMServiceImpl(instance: instance)
  let serviceAdmin = serviceImpl.asVMServiceAdmin

  await instance.registerRestorer(
    proc(d: CapDescription): Future[AnyPointer] =
      case d.category:
      of "vm:vm":
        return launch(serviceImpl, d.description.castAs(LaunchConfiguration), runtimeId=d.runtimeId).toAnyPointerFuture
      else:
        return error(AnyPointer, "unknown category"))


  await instance.runService(
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=serviceAdmin.castAs(ServiceAdmin)
  )

when isMainModule:
  main().runMain()
