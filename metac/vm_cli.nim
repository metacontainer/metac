import metac/cli_common, parseopt3, metac/fs_cli, metac/stream_cli, metac/network_cli

proc writeHelp() =
  echo("""
Usage: metac vm run [args...]

  --network driver=virtio|e1000,uri=URI       Attach a network interface to the VM
  -m, --memory M                              Memory in MiB
  --foreground                                Run in foreground
  --boot kernel=URI,initrd=URI,append=args    Directly boot kernel
  --drive driver=virtio|ide,uri=URI           Attach a disk
  --serial driver=default|virtio,nowait=true|false,name=NAME,uri=URI
      Attach a serial port
  --vcpu N                                    Number of virtual CPUs
""")
  quit(1)

proc parseComplexArg(arg: string, required: openarray[string] = @[], optional: openarray[string] = @[]): Table[string, string] =
  result = initTable[string, string]()

  for fragment in arg.split(","):
    if "=" notin fragment:
      raise newException(Exception, arg & ":expected '=' in argument")

    let s = fragment.split("=", 1)

    if s[0] notin required and s[0] notin optional:
      raise newException(Exception, arg & ": invalid key $1" % s[0])

    if s[0] in result:
      raise newException(Exception, arg & ": key $1 given twice" % s[0])

    result[s[0]] = s[1]

  for key in required:
    if key notin result:
      raise newException(Exception, arg & ": missing key $1" % key)

proc mainRun() {.async.} =
  let instance = await newInstance()
  let config = LaunchConfiguration(
    boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.disk))

  var printStreams: seq[int] = @[]
  var printNetworks: seq[int] = @[]
  var persistent = false
  var foreground = false

  for kind, key, val in getopt(cmdline = argv, longBools = @["foreground", "persistent"]):
    case kind:
    of cmdArgument:
      quit("no positional arguments expected")
    of cmdLongOption, cmdShortOption:
      case key:
      of "persistent":
        persistent = true
      of "m", "memory":
        config.memory = parseInt(val).uint32
      of "vcpu", "cpu":
        config.vcpu = parseInt(val).int32
      of "foreground":
        foreground = true
      of "boot":
        let args = parseComplexArg(val, required=["kernel"], optional=["initrd", "cmdline"])

        config.boot.reset()
        config.boot.kind = LaunchConfiguration_BootKind.kernel

        if "kernel" in args:
          config.boot.kernel.kernel = await fileFromUri(instance, args["kernel"])
        if "initrd" in args:
          config.boot.kernel.initrd = await fileFromUri(instance, args["initrd"])
        if "cmdline" in args:
          config.boot.kernel.cmdline = args["cmdline"]
      of "serial":
        let args = parseComplexArg(val, required=["driver"], optional=["name", "nowait", "uri"])
        let serial = SerialPort()

        if "driver" in args:
          serial.driver = parseEnum[SerialPort_Driver](args["driver"])
        if "name" in args:
          serial.name = args["name"]
        if "uri" in args:
          serial.stream = await streamFromUri(instance, args["uri"])
        else:
          printStreams.add config.serialPorts.len
        if "nowait" in args:
          serial.nowait = args["nowait"] == "yes"

        config.serialPorts.add serial
      of "network":
        let args = parseComplexArg(val, required=["driver"], optional=["uri"])
        let network = Network()

        if "driver" in args:
          network.driver = parseEnum[Network_Driver](args["driver"])
        if "uri" in args:
          network.network = await netFromUri(instance, args["uri"])
        else:
          printNetworks.add config.networks.len

        config.networks.add network
      else:
        stderr.writeLine "invalid option ", key
        writeHelp()
    of cmdEnd: assert(false)

  let serv = await instance.getServiceAdmin("vm", VMServiceAdmin)
  let launcher = await serv.getLauncher
  let vm = await launcher.launch(config)

  let sref = await vm.castAs(Persistable).createSturdyRef(nullCap, persistent)
  echo sref.formatSturdyRef

  for i in printStreams:
    let sref = await vm.serialPort(i.int32).castAs(Persistable).createSturdyRef(nullCap, persistent)
    echo "stream: ", sref.formatSturdyRef

  for i in printNetworks:
    let sref = await vm.network(i.int32).castAs(Persistable).createSturdyRef(nullCap, persistent)
    echo "network: ", sref.formatSturdyRef

  if foreground:
    await vm.castAs(Waitable).wait

proc main*() =
  dispatchSubcommand({
    "run": () => mainRun().runMain,
  })
