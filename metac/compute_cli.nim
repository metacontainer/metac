import reactor, capnp, metac/instance, metac/schemas, metac/stream, metac/persistence, metac/cli_common, metac/fs_cli, metac/stream_cli, metac/network_cli, strutils, collections, cligen, parseopt3, posix, sequtils, metac/simple_pty

proc writeHelp() =
  echo("""
Usage: metac run [--fd=fd...] [args...]

  --fd num         Pass FD `num` to the program
  --fd target=num  Pass FD `num` to the program as `target`
  --fd target=URI  Pass stream `URI` to the program as `target` FD
  --fd target1,target2,...=num  Targets may also be a comma separated list of FDs
  --pty            Run program in PTY/TTY.
  -m, --memory     Memory in MiB
  --uid --gid      Change UID or GID of the process
  --background     Run in background
  --network name=[name],uri=[uri],ip=[address1],ip=[address1],route=[network] [via] Attach a network
  --env K=V        Set an environment variable.
  --env-only       Only spawn the environment (without any processes) and return reference to it
  --env-ref        Spawn the process in an existing environment
""")
  quit(1)

proc runCmd() {.async.} =
  let instance = await newInstance()

  var serviceName = "computevm"
  var wait: bool = true
  var persistent: bool = false

  let envDescription = ProcessEnvironmentDescription(
    filesystems: @[],
    networks: @[],
    memory: 1024,

  )
  var processDescription = ProcessDescription(
    args: @[],
    files: @[],
    envVars: @[],
  )

  # Were any process options given?
  var processConfig = false
  # Were any environment options given?
  var envConfig = false

  var envOnly = false
  var envRef: ProcessEnvironment = nullCap
  var existingEnv = false

  for kind, key, val in getopt(cmdline = argv, longBools = @["pty", "persistent", "env-only"]):
    case kind
    of cmdArgument:
      processDescription.args.add key
      processConfig = true
    of cmdLongOption, cmdShortOption:
      case key:
      of "fd", "pty":
        processConfig = true
        var val = val

        if val == nil:
          if key == "fd":
            asyncRaise "--fd option requires argument"
          else:
            val = "0,1,2=0" # sensible default for --pty

        if "=" notin val:
          val = val & "=" & val

        let s = val.split("=", 1)
        let targets = s[0].split(",").map(x => parseInt(x).uint32)

        var wrapped: Stream

        if key == "pty":
          # TODO: make terminal `raw` later (or reopen stdio to slave?)
          let stream = await wrapClientTTY(dup(parseInt(s[1]).cint))
          wrapped = wrapStream(instance, stream)
        else:
          if ":" in s[1]: # URI
            wrapped = await streamFromUri(instance, s[1])
          else:
            wrapped = wrapStreamFd(instance, dup(parseInt(s[1]).cint))

        processDescription.files.add FD(stream: wrapped, targets: targets, isPty: key == "pty")
      of "network":
        envConfig = true
        var networkInterface = NetworkInterface(addresses: @[], routes: @[])
        for fragment in val.split(","):
          if "=" notin fragment:
            asyncRaise("invalid network description ($1)" % fragment)

          let s = fragment.split("=", 1)
          case s[0]:
          of "name": networkInterface.name = s[1]
          of "uri": networkInterface.l2interface = await netFromUri(instance, s[1])
          of "address", "ip": networkInterface.addresses.add(s[1])
          of "route":
            let r = s[1].split(" ", 1)
            let routeInfo = NetworkInterface_Route(network: r[0])
            if r.len == 2: routeInfo.via = r[1]
            networkInterface.routes.add(routeInfo)
          else:
            asyncRaise("invalid network description ($1)" % fragment)

        envDescription.networks.add networkInterface
      of "help", "h":
        writeHelp()
      of "memory", "m":
        envConfig = true
        envDescription.memory = parseInt(val).uint32
      of "mount":
        envConfig = true
        if "=" notin val:
          asyncRaise "--mount option expected argument in format: <mountpoint>=<fs URI>"

        let s = val.split("=", 1)
        let mountpoint = s[0]
        let fs = await fsFromUri(instance, s[1])

        envDescription.filesystems.add(FsMount(path: mountpoint, fs: fs))
      of "env", "e":
        processConfig = true

        if "=" notin val:
          asyncRaise "= not in environment variable"

        processDescription.envVars.add val
      of "background", "f":
        wait = false
      of "persistent", "p":
        persistent = true
      of "service":
        envConfig = true
        serviceName = val
      of "uid":
        processConfig = true
        processDescription.uid = parseInt(val).uint32
      of "gid":
        processConfig = true
        processDescription.gid = parseInt(val).uint32
      of "env-only":
        envOnly = true
        envConfig = true
      of "env-ref":
        processConfig = true
        existingEnv = true
        envRef = await instance.restore(val.parseSturdyRef).castAs(ProcessEnvironment)
      else:
        stderr.writeLine "invalid option ", key
        writeHelp()
    of cmdEnd: assert(false) # cannot happen

  if envOnly and processConfig:
    asyncRaise "--env-only and process specific options given at the same time"

  if existingEnv and envConfig:
    asyncRaise "--env-ref and environment specific options given at the same time"

  if envOnly:
     processDescription = nil
  else:
    if processDescription.args.len == 0:
      asyncRaise "command missing"

  var process: Process

  if not existingEnv:
    let launcher = await instance.getServiceAdmin(serviceName, ComputeLauncher)
    let r = await launcher.launch(processDescription, envDescription)
    process = r.process

    if envOnly:
      let sref = await r.env.castAs(schemas.Persistable).createSturdyRef(nullCap, persistent)
      echo sref.formatSturdyRef
  else:
    process = await envRef.launchProcess(processDescription)

  if not envOnly:
    if persistent:
      let sref = await process.castAs(schemas.Persistable).createSturdyRef(nullCap, true)
      stderr.writeLine("process id: ", sref.formatSturdyRef)

    if wait:
      await process.wait

proc mainRun*() =
  runCmd().runMain
