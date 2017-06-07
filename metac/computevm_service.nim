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
    env: ProcessEnvironmentImpl

proc file(self: ProcessImpl, index: uint32): Future[Stream] {.async.} =
  discard

proc kill(self: ProcessImpl, signal: uint32): Future[void] {.async.} =
  discard

proc returnCode(self: ProcessImpl, ): Future[int32] {.async.} =
  discard

proc wait(self: ProcessImpl, ): Future[void] {.async.} =
  discard

capServerImpl(ProcessImpl, [Process])

proc launchProcess(self: ProcessEnvironmentImpl, description: ProcessDescription): Future[Process] {.async.}

proc network(self: ProcessEnvironmentImpl, index: uint32): Future[L2Interface] {.async.} =
  discard

capServerImpl(ProcessEnvironmentImpl, [ProcessEnvironment])

proc randomAgentNetwork(): IpInterface =
  var arr: array[16, uint8]
  arr[0] = 0xFC
  for i in 1..15:
    arr[i] = uint8(random(256))
  arr[15] = arr[15] and uint8(0b11111100)
  return (arr.Ip6Address.from6, 126)

proc runAgentServer(env: ProcessEnvironmentImpl): Future[void] {.async.} =
  let server = await createTcpServer(5600, $env.myAddress)
  echo "agent server listening at ", $env.myAddress, " ", 5600
  let conn = await server.incomingConnections.receive
  server.incomingConnections.recvClose(JustClose)

  proc agentInit(agentEnv: AgentEnv): Future[ProcessEnvironmentDescription] =
    if env.agentEnv.getFuture.isCompleted: asyncRaise "double init"
    env.agentEnv.complete(agentEnv)
    return just(env.description)

  discard newTwoPartyServer(conn, inlineCap(AgentBootstrap, AgentBootstrapInlineImpl(
    init: agentInit
  )).toCapServer)

proc launchEnv(self: ComputeVmService, envDescription: ProcessEnvironmentDescription): Future[ProcessEnvironment] {.async.} =
  let env = ProcessEnvironmentImpl(instance: self.instance)
  env.agentEnv = newCompleter[AgentEnv]()
  env.description = envDescription

  let kernel = localFile(self.instance, getCurrentDir() / "build/vmlinuz")
  let initrd = localFile(self.instance, getCurrentDir() / "build/initrd.cpio")
  var cmdline = "console=ttyS0 "

  let netNamespace = await self.instance.getServiceAdmin("network", NetworkServiceAdmin).rootNamespace
  let localDevName = "mcag" & hexUrandom(5)
  let localDev = await netNamespace.createInterface(localDevName).l2interface

  var additionalNetworks: seq[Network] = @[]

  # TODO(security): put the agent network in a separate net namespace
  let agentIpNetwork = randomAgentNetwork()
  env.myAddress = agentIpNetwork.nthAddress(1)
  env.agentAddress = agentIpNetwork.nthAddress(2)

  cmdline &= " metac.agentaddress=" & $(env.agentAddress) & " metac.serviceaddress=" & $(env.myAddress) & " metac.agentnetwork=" & ($agentIpNetwork)
  await execCmd(@["sysctl", "-w", "net.ipv6.conf." & localDevName & ".accept_dad=0"])
  await execCmd(@["sysctl", "-w", "net.ipv6.conf." & localDevName & ".forwarding=1"])
  await execCmd(@["ip", "address", "add", ($env.myAddress) & "/126", "dev", localDevName])


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

  env.runAgentServer().ignore

  let vm = await self.launcher.launch(vmConfig)
  env.vm = vm

  proc serialPortHandler() {.async.} =
    let portStream = await vm.serialPort(0)
    let (port, holder) = await self.instance.unwrapStreamAsPipe(portStream)
    asyncFor line in port.input.lines:
      echo "[vm] ", line.strip(leading=false)

    fakeUsage(holder)

  serialPortHandler().ignore

  return env.asProcessEnvironment

proc launchProcess(self: ProcessEnvironmentImpl, description: ProcessDescription): Future[Process] {.async.} =
  if description.isNil:
    return nullCap

  let process = ProcessImpl(instance: self.instance, env: self)
  return process.asProcess

proc launch(self: ComputeVmService, processDescription: ProcessDescription,
            envDescription: ProcessEnvironmentDescription): Future[ComputeLauncher_launch_Result] {.async.} =
  let env = await self.launchEnv(envDescription)
  let process = await env.launchProcess(processDescription)
  return ComputeLauncher_launch_Result(process: process, env: env)

capServerImpl(ComputeVmService, [ComputeLauncher])


proc addRule(table: string, rule: string) =
  if execShellCmd("ip6tables -t $1 -C $2 2>/dev/null" % [table, rule]) != 0:
    let ok = execShellCmd("iptables -t $1 -A $2"  % [table, rule])
    if ok != 0:
      raise newException(Exception, "can't add iptables rule: " & rule)

proc init() =
  # TODO: proxy instead of NATting or don't use network device at all (use virtio-serial)
  discard execShellCmd("ipset create metacvmnat hash:ip")
  addRule("nat", "POSTROUTING -m set --match-set metacvmnat src -j MASQUERADE")

proc main*() {.async.} =
  init()
  let instance = await newServiceInstance("computevm")

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
