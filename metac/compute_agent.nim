import metac/instance, metac/schemas, reactor, capnp, caprpc, os, times, collections, metac/computevm_internal_schema, posix

proc parseKernelCmdline(line: string): TableRef[string, string] =
  result = newTable[string, string]()
  for part in line.strip.split(' '):
    let s = part.split('=')
    if s.len == 2:
      result[s[0]] = s[1]

proc shutdown =
  discard execShellCmd("echo o > /proc/sysrq-trigger")
  sleep(5000)

type AgentEnvImpl = ref object of RootObj
  discard

capServerImpl(AgentEnvImpl, [AgentEnv])

proc main {.async.} =
  doAssert 0 == execShellCmd("""
mkdir -p /proc /sys /dev
set -e
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mkdir -p /dev/pts
mount -t devpts pts /dev/pts
""")

  let options = parseKernelCmdline(readFile("/proc/cmdline"))


  #doAssert 0 == execShellCmd("echo ip link set dev eth0 up")
  #doAssert 0 == execShellCmd("echo ip address add $1/126 dev eth0" % options["metac.agentaddress"])
  #doAssert 0 == execShellCmd("echo ip route add $1 dev eth0" % ($options["metac.agentnetwork"]))

  doAssert 0 == execShellCmd("sysctl -w net.ipv6.conf.eth0.accept_dad=0")
  doAssert 0 == execShellCmd("ip link set dev lo up")
  doAssert 0 == execShellCmd("ip link set dev eth0 up")
  doAssert 0 == execShellCmd("ip address add $1/126 dev eth0" % options["metac.agentaddress"])

  let env = AgentEnvImpl()

  await asyncSleep(1000)
  echo "connecting (", options["metac.serviceaddress"], ")..."
  let conn = await connectTcp(parseAddress(options["metac.serviceaddress"]), 5600)
  echo "done"
  let bootstrapCap = await newTwoPartyClient(conn).bootstrap.castAs(AgentBootstrap)
  let envDescription = await bootstrapCap.init(env.asAgentEnv)
  echo envDescription.pprint

proc forkAgent =
  let agentPid = fork()
  assert agentPid >= 0
  if agentPid == 0:
    main().runMain
  else:
    while true:
      var status: cint = 0
      let pid = wait(addr status)
      if pid == agentPid:
        echo "Agent main process died."
        sleep(500) # finish printing error message
        shutdown()

when isMainModule:
  forkAgent()
