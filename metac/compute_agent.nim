import metac/instance, metac/schemas, reactor, capnp, caprpc, os, times, collections, metac/computevm_internal_schema, posix, metac/fs, reactor/process, metac/stream

proc parseKernelCmdline(line: string): TableRef[string, string] =
  result = newTable[string, string]()
  for part in line.strip.split(' '):
    let s = part.split('=')
    if s.len == 2:
      result[s[0]] = s[1]

proc shutdown =
  discard execShellCmd("echo o > /proc/sysrq-trigger")
  sleep(5000)

type
  AgentEnvImpl = ref object of RootObj
    instance: Instance
    ready: Future[void]

  ProcessImpl = ref object of RootObj
    process: process.Process
    holders: seq[Holder]

proc file(self: ProcessImpl, index: uint32): Future[Stream] {.async.} =
  return nullCap

proc kill(self: ProcessImpl, signal: uint32): Future[void] {.async.} =
  return

proc returnCode(self: ProcessImpl, ): Future[int32] {.async.} =
  return 0

proc wait(self: ProcessImpl, ): Future[void] {.async.} =
  return

capServerImpl(ProcessImpl, [schemas.Process])

proc launchProcess(self: AgentEnvImpl, d: ProcessDescription): Future[schemas.Process] {.async.} =
  await self.ready

  var additionalFiles: seq[tuple[target: cint, src: cint]] = @[]

  defer:
    for f in additionalFiles:
      discard close(f.src)

  for i, fd in d.files:
    let (unwrappedFd, holder) = await self.instance.unwrapStream(fd.stream)
    additionalFiles.add((i.cint, unwrappedFd))

  let process = startProcess(d.args, additionalFiles = additionalFiles)

  return ProcessImpl(process: process).asProcess

capServerImpl(AgentEnvImpl, [AgentEnv])

proc chroot(path: cstring): cint {.importc, header: "<unistd.h>".}

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

  doAssert 0 == execShellCmd("sysctl -w net.ipv6.conf.eth0.accept_dad=0")
  doAssert 0 == execShellCmd("ip link set dev lo up")
  doAssert 0 == execShellCmd("ip link set dev eth0 up")
  doAssert 0 == execShellCmd("ip address add $1/126 dev eth0" % options["metac.agentaddress"])
  doAssert 0 == execShellCmd("ip -6 route add default via $1" % options["metac.serviceaddress"])

  let readyCompleter = newCompleter[void]()
  let env = AgentEnvImpl(
    # simplified instance
    instance: Instance(address: options["metac.agentaddress"]),
    ready: readyCompleter.getFuture,
  )

  await asyncSleep(1000)
  echo "connecting (", options["metac.serviceaddress"], ")..."
  let conn = await connectTcp(parseAddress(options["metac.serviceaddress"]), 5600)
  echo "done"
  let bootstrapCap = await newTwoPartyClient(conn).bootstrap.castAs(AgentBootstrap)
  let envDescription = await bootstrapCap.init(env.asAgentEnv)

  var holders: seq[Holder] = @[]

  createDir("/mnt")

  echo envDescription.pprint
  echo "mounting filesystems..."
  for fs in envDescription.filesystems:
    echo fs.path, "..."
    createDir("/mnt/" & fs.path)
    let holder = await mount(env.instance, "/mnt/" & fs.path, fs.fs)
    holders.add holder

  # TODO: pivot_root?
  if chroot("/mnt") != 0:
    echo "chroot failed"
    return

  echo "setup done"
  readyCompleter.complete
  await waitForever()

  fakeUsage holders

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
