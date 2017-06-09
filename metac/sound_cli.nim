import reactor, capnp, metac/instance, metac/schemas, metac/stream, metac/persistence, metac/cli_common, strutils, collections, cligen, metac/sound_schema

proc soundDeviceFromUri*(instance: Instance, uri: string): Future[SoundDevice] {.async.} =
  let s = uri.split(":", 1)
  let schema = s[0]
  let path = if s.len > 1: s[1] else: ""

  let soundService = await instance.getServiceAdmin("sound", SoundServiceAdmin)
  let ns = soundService.getSystemMixer

  if schema == "localsink":
    return ns.getSink(path)
  elif schema == "localsource":
    return ns.getSource(path)
  elif schema == "newlocalsink":
    return ns.createSink(path)
  elif schema == "newlocalsource":
    return ns.createSource(path)
  elif schema == "ref":
    return instance.restore(uri.parseSturdyRef).castAs(SoundDevice)
  else:
    raise newException(ValueError, "invalid URI")

proc exportCmd(uri: string, persistent=false) =
  if uri == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let dev = await instance.soundDeviceFromUri(uri)
    let sref = await dev.castAs(schemas.Persistable).createSturdyRef(nullCap, persistent)
    echo sref.formatSturdyRef

dispatchGen(exportCmd)

proc bindCmd(uri1: string, uri2: string, persistent=false) =
  if uri1 == nil or uri2 == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let dev1 = await instance.soundDeviceFromUri(uri1)
    let dev2 = await instance.soundDeviceFromUri(uri2)
    let holder = await dev1.bindTo(dev2)
    let sref = await holder.castAs(Persistable).createSturdyRef(nullCap, persistent)
    echo sref.formatSturdyRef

dispatchGen(bindCmd)

proc listCmd() =
  asyncMain:
    let instance = await newInstance()
    let soundService = await instance.getServiceAdmin("sound", SoundServiceAdmin)
    let devList = await soundService.getSystemMixer.getDevices
    for dev in devList:
      let info = await dev.info()
      echo info.name

dispatchGen(listCmd)

proc main*() =
  dispatchSubcommand({
    "export": () => quit(dispatchExportCmd(argv, doc="")),
    "bind": () => quit(dispatchBindCmd(argv, doc="")),
    "ls": () => quit(dispatchListCmd(argv, doc=""))
  })
