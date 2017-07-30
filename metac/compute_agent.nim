import metac/instance, metac/schemas, reactor, capnp, caprpc, os, times, collections, metac/computevm_internal_schema, posix, metac/fs, reactor/process, metac/stream, reactor/ipaddress, osproc, sequtils, metac/simple_pty

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
  # implemented by the service
  return nullCap

proc kill(self: ProcessImpl, signal: uint32): Future[void] {.async.} =
  self.process.kill
  return

proc returnCode(self: ProcessImpl, ): Future[int32] {.async.} =
  let code = self.process.wait
  if code.isCompleted:
    return code.get.int32
  else:
    return -1

proc wait(self: ProcessImpl, ): Future[void] {.async.} =
  discard (await self.process.wait)

capServerImpl(ProcessImpl, [schemas.Process])

proc launchProcess(self: AgentEnvImpl, d: ProcessDescription): Future[schemas.Process] {.async.} =
  await self.ready

  var additionalFiles: seq[tuple[target: cint, src: cint]] = @[]
  let processImpl = ProcessImpl(holders: @[])

  echo "launch", d.pprint
  defer:
    for f in additionalFiles:
      discard close(f.src)

  for fd in d.files:
    var srcFd: cint
    if fd.isPty:
      let stream = await self.instance.unwrapStreamAsPipe(fd.stream)
      srcFd = await createServerTTY(stream)
    else:
      let (unwrappedFd, holder) = await self.instance.unwrapStream(fd.stream)
      processImpl.holders.add(holder)
      srcFd = unwrappedFd

    for num in fd.targets:
      additionalFiles.add((num.cint, srcFd))

  let additionalEnv = d.envVars.map(x => split2(x, "="))

  processImpl.process = startProcess(d.args,
                                     detached = true,
                                     additionalFiles = additionalFiles,
                                     additionalEnv = additionalEnv,
                                     uid = d.uid.int, gid = d.gid.int)

  return processImpl.asProcess

capServerImpl(AgentEnvImpl, [AgentEnv])

proc chroot(path: cstring): cint {.importc, header: "<unistd.h>".}

proc execCmd(s: string) =
  doAssert 0 == execShellCmd(s)

proc execCmd(args: seq[string]) =
  execCmd(args.map(x => quoteShell(x)).join(" "))

proc unsetenv(name: cstring): cint {.importc, discardable.}

proc main {.async.} =
  execCmd("""
mkdir -p /proc /sys /dev /mnt
set -e

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mkdir -p /dev/pts
mount -t devpts pts /dev/pts
""")

  unsetenv("TERM")

  let options = parseKernelCmdline(readFile("/proc/cmdline"))

  execCmd("sysctl -w net.ipv6.conf.eth0.accept_dad=0")
  execCmd("ip link set dev lo up")
  execCmd("ip link set dev eth0 up")
  execCmd("ip address add $1/126 dev eth0" % options["metac.agentaddress"])
  execCmd("ip -6 route add default via $1" % options["metac.serviceaddress"])

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

  # Filesystems
  echo "mounting filesystems..."
  for fs in envDescription.filesystems:
    echo fs.path, "..."
    createDir("/mnt/" & fs.path)
    let (holder, onFinish) = await mount(env.instance, "/mnt/" & fs.path, fs.fs)
    holders.add holder
    # TODO(?): remount

  execCmd("""
mkdir -p /mnt/proc /mnt/sys /mnt/dev
mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
mount -t devtmpfs dev /mnt/dev
mkdir -p /mnt/dev/pts
mount -t devpts pts /mnt/dev/pts
""")

  # Network
  echo "setting up network..."
  for i, net in envDescription.networks:
    var name = "eth" & ($(i + 1))

    if net.name != nil:
       execCmd(@["ip", "link", "set", "dev", name, "name", net.name])
       name = net.name

    execCmd(@["ip", "link", "set", "dev", name, "up"])

    for address0 in net.addresses:
      var address = address0
      if '/' in address:
        address = $parseInterface(address)
      else:
        address = $parseAddress(address)
      execCmd(@["ip", "address", "add", "dev", name, address])

    for route in net.routes:
      if route.via == nil:
        execCmd(@["ip", "route", "add", $parseInterface(route.network), "dev", name])
      else:
        execCmd(@["ip", "route", "add", $parseInterface(route.network), $parseAddress(route.via)])

  # TODO: pivot_root?
  if chroot("/mnt") != 0:
    echo "chroot failed"
    return

  discard chdir("/")

  await asyncSleep(100)

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
