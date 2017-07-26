import reactor, capnp, metac/instance, metac/schemas, metac/stream, metac/persistence, metac/cli_common, metac/fs_cli, metac/stream_cli, strutils, collections, cligen, parseopt3, posix, sequtils, metac/simple_pty

proc writeHelp() =
  echo("""
Usage: metac run [--fd=fd...] [args...]

  --fd num         Pass FD `num` to the program
  --fd target=num  Pass FD `num` to the program as `target`
  --fd target=URI  Pass stream `URI` to the program as `target` FD
  --fd target1,target2,...=num  Targets may also be a comma separated list of FDs
  -m, --memory     Memory in MiB
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
  let processDescription = ProcessDescription(
    args: @[],
    files: @[]
  )

  for kind, key, val in getopt(cmdline=argv):
    case kind
    of cmdArgument:
      processDescription.args.add key
    of cmdLongOption, cmdShortOption:
      case key:
      of "fd", "pty":
        var val = val
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
      of "help", "h":
        writeHelp()
      of "memory", "m":
        envDescription.memory = parseInt(val).uint32
      of "mount":
        if "=" notin val:
          asyncRaise "--mount option expected argument in format: <mountpoint>=<fs URI>"

        let s = val.split("=", 1)
        let mountpoint = s[0]
        let fs = await fsFromUri(instance, s[1])

        envDescription.filesystems.add(FsMount(path: mountpoint, fs: fs))
      of "background", "f":
        wait = false
      of "persistent", "p":
        persistent = true
      of "service":
        serviceName = val
      else:
        stderr.writeLine "invalid option ", key
        writeHelp()
    of cmdEnd: assert(false) # cannot happen

  let launcher = await instance.getServiceAdmin(serviceName, ComputeLauncher)
  let r = await launcher.launch(processDescription, envDescription)
  let (env, process) = (r.env, r.process)

  if persistent:
    let sref = await process.castAs(schemas.Persistable).createSturdyRef(nullCap, true)
    stderr.writeLine("process id: ", sref.formatSturdyRef)

  if wait:
    await process.wait

proc mainRun*() =
  runCmd().runMain
