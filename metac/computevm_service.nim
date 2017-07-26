# Implements the ComputeLauncher using VMLauncher.
import reactor, caprpc, capnp, metac/schemas, metac/instance, metac/persistence, metac/fs, os, collections, random, metac/process_util, metac/stream, metac/computevm_internal_schema

type
  ComputeVmService = ref object of RootObj
    instance: ServiceInstance
    launcher: VMLauncher

  ProcessEnvironmentImpl = ref object of RootObj
    instance: ServiceInstance
    description: ProcessEnvironmentDescription
    agentAddress: IpAddress
    myAddress: IpAddress
    vm: VM
    agentEnv: Completer[AgentEnv]

  ProcessImpl = ref object of RootObj
    instance: ServiceInstance
    files: seq[Stream]
    wrapped: Process
    env: ProcessEnvironmentImpl

proc file(self: ProcessImpl, index: uint32): Future[Stream] {.async.} =
  let index = index.int
  if index < 0 or index >= self.files.len:
    asyncRaise "index error"

  return self.files[index]

proc kill(self: ProcessImpl, signal: uint32): Future[void] {.async.} =
  await self.wrapped.kill(signal)

proc returnCode(self: ProcessImpl, ): Future[int32] {.async.} =
  return self.wrapped.returnCode

proc wait(self: ProcessImpl, ): Future[void] {.async.} =
  await self.wrapped.wait

capServerImpl(ProcessImpl, [Process])

proc launchProcess(self: ProcessEnvironmentImpl, description: ProcessDescription): Future[Process] {.async.}

proc network(self: ProcessEnvironmentImpl, index: uint32): Future[L2Interface] {.async.} =
  discard

proc destroyProcessEnvironment(self: ProcessEnvironmentImpl) =
  echo "destroy ProcessEnvironmentImpl"
  self.vm.destroy().ignore

proc destroy(self: ProcessEnvironmentImpl): Future[void] {.async.} =
  destroyProcessEnvironment(self)

capServerImpl(ProcessEnvironmentImpl, [ProcessEnvironment, Destroyable])

proc randomAgentNetwork(): IpInterface =
  var arr: array[16, uint8]
  arr[0] = 0xFC
  let d = urandom(16)
  for i in 1..15:
    arr[i] = uint8(d[i])
  arr[15] = arr[15] and uint8(0b11111100)
  return (arr.Ip6Address.from6, 126)

proc runAgentServer(env: ProcessEnvironmentImpl): Future[void] {.async.} =
  let server = await createTcpServer(5600, $env.myAddress)
  echo "agent server listening at ", $env.myAddress, " ", 5600
  let conn = await server.incomingConnections.receive
  server.incomingConnections.recvClose(JustClose)

  let initImpl = AgentBootstrapInlineImpl()

  proc agentInit(agentEnv: AgentEnv): Future[ProcessEnvironmentDescription] =
    initImpl.init = nil # unset init method to allow GC to free the environ
    env.agentEnv.complete(agentEnv)
    return just(env.description)

  initImpl.init = agentInit

  discard newTwoPartyServer(conn, inlineCap(AgentBootstrap, initImpl).toCapServer)

proc proxyStream(instance: Instance, myAddress: string, stream: Stream): Stream =
  proc getStream(): Future[BytePipe] =
    return instance.unwrapStreamAsPipe(stream)

  let fakeInstance = Instance(address: myAddress)
  return fakeInstance.wrapStream(getStream)

proc proxyFs(instance: Instance, myAddress: string, fs: Filesystem): Filesystem =
  proc v9fsStreamImpl: Future[Stream] {.async.} =
    let stream = await fs.v9fsStream()
    return proxyStream(instance, myAddress, stream)

  return inlineCap(Filesystem, FilesystemInlineImpl(
    v9fsStream: v9fsStreamImpl
  ))


proc serialPortHandler(instance: Instance, s: Stream) {.async.} =
  let port = await instance.unwrapStreamAsPipe(s)
  asyncFor line in port.input.lines:
    echo "[vm] ", line.strip(leading=false)

const kernelPath {.strdefine.} = "vmlinuz"
const initrdPath {.strdefine.} = "initrd.cpio"

proc launchEnv(self: ComputeVmService, envDescription: ProcessEnvironmentDescription): Future[ProcessEnvironment] {.async.} =
  var env: ProcessEnvironmentImpl
  new(env, destroyProcessEnvironment)
  env.instance = self.instance
  env.agentEnv = newCompleter[AgentEnv]()
  env.description = envDescription

  let kernel = localFile(self.instance, expandFilename(getAppDir() / kernelPath))
  let initrd = localFile(self.instance, expandFilename(getAppDir() / initrdPath))
  var cmdline = "console=ttyS0 "

  let netNamespace = await self.instance.getServiceAdmin("network", NetworkServiceAdmin).rootNamespace
  let localDevName = "mcag" & hexUrandom(5)
  let localDev = await netNamespace.createInterface(localDevName).l2interface

  var additionalNetworks: seq[Network] = @[]

  # TODO(security): put the agent network in a separate net namespace
  let agentIpNetwork = randomAgentNetwork()
  env.myAddress = agentIpNetwork.nthAddress(1)
  env.agentAddress = agentIpNetwork.nthAddress(2)

  cmdline &= " metac.agentaddress=" & $(env.agentAddress) & " metac.serviceaddress=" & $(env.myAddress) & " metac.agentnetwork=" & ($agentIpNetwork) & " quiet"
  # Duplicate Address Discovery may cause bind to fail with "address not available" and is not applicable here
  await execCmd(@["sysctl", "-w", "net.ipv6.conf." & localDevName & ".accept_dad=0"])
  await execCmd(@["sysctl", "-w", "net.ipv6.conf." & localDevName & ".forwarding=1"])
  await execCmd(@["ip", "address", "add", ($env.myAddress) & "/126", "dev", localDevName])
  await execCmd(@["ip", "address", "show", "dev", localDevName])

  for mount in envDescription.filesystems:
    mount.fs = proxyFs(env.instance, $env.myAddress, mount.fs)

  for network in envDescription.networks:
    additionalNetworks.add Network(driver: Network_Driver.virtio, network: network.l2interface)
    network.l2interface = nullCap

  let vmConfig = LaunchConfiguration(
    memory: envDescription.memory,
    vcpu: 1,
    machineInfo: MachineInfo(`type`: MachineInfo_Type.host),
    serialPorts: @[
      # the console serial
      SerialPort(
        driver: SerialPort_Driver.default,
        nowait: false
      )
    ],
    boot: LaunchConfiguration_Boot(
      kind: LaunchConfiguration_BootKind.kernel,
      kernel: LaunchConfiguration_KernelBoot(
        kernel: kernel,
        initrd: initrd,
        cmdline: cmdline)),
    networks: @[
      Network(driver: Network_Driver.virtio, network: localDev)
    ] & additionalNetworks,
    drives: @[]
  )

  runAgentServer(env).ignore

  let vm = await self.launcher.launch(vmConfig)
  env.vm = vm

  let portStream = await vm.serialPort(0)
  serialPortHandler(env.instance, portStream).ignore

  return env.asProcessEnvironment

proc launchProcess(self: ProcessEnvironmentImpl, description: ProcessDescription): Future[Process] {.async.} =
  if description.isNil:
    return nullCap

  if description.files == nil: description.files = @[]
  if description.args == nil: description.args = @[]

  if description.args.len < 1: asyncRaise "missing args"

  let process = ProcessImpl(instance: self.instance, env: self, files: @[])

  # Fill in null files
  for i in 0..<description.files.len:
    if description.files[i].stream.isNil:
      let (a, b) = newStreamPair(self.instance)
      process.files.add a
      description.files[i].stream = b
    else:
      process.files.add nullCap

    description.files[i].stream = proxyStream(self.instance, $self.myAddress, description.files[i].stream)

  let agentEnv = await self.agentEnv.getFuture
  let wrappedProcess = await agentEnv.launchProcess(description)
  process.wrapped = wrappedProcess
  return process.asProcess

proc launch(self: ComputeVmService, processDescription: ProcessDescription,
            envDescription: ProcessEnvironmentDescription): Future[ComputeLauncher_launch_Result] {.async.} =
  let env = await self.launchEnv(envDescription)
  let process = await env.launchProcess(processDescription)
  return ComputeLauncher_launch_Result(process: process, env: env)

capServerImpl(ComputeVmService, [ComputeLauncher])

proc main*() {.async.} =
  enableGcNoDelay()
  let instance = await newServiceInstance("computevm")

  await instance.waitForService("vm")
  let vmLauncher = await instance.getServiceAdmin("vm", VMServiceAdmin).getLauncher
  let serviceImpl = ComputeVmService(instance: instance, launcher: vmLauncher)
  let serviceAdmin = serviceImpl.asComputeLauncher

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
