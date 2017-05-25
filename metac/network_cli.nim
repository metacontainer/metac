import reactor, capnp, metac/instance, metac/schemas, metac/stream, metac/persistence, metac/cli_common, strutils, collections, cligen

proc netFromUri*(instance: Instance, uri: string): Future[L2Interface] {.async.} =
  let s = uri.split(":", 1)
  let schema = s[0]
  let path = s[1]

  let netService = await instance.getServiceAdmin("network", NetworkServiceAdmin)
  let ns = await netService.rootNamespace

  if schema == "local":
    return ns.getInterface(path).l2interface
  if schema == "newlocal":
    return ns.createInterface(path).l2interface
  elif schema == "ref":
    return instance.restore(uri.parseSturdyRef).castAs(L2Interface)
  else:
    raise newException(ValueError, "invalid URI")

proc exportCmd(uri: string, persistent=false) =
  if uri == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let file = await instance.netFromUri(uri)
    let sref = await file.castAs(schemas.Persistable).createSturdyRef(nullCap, persistent)
    echo sref.formatSturdyRef

dispatchGen(exportCmd)

proc bindCmd(uri1: string, uri2: string, persistent=false) =
  if uri1 == nil or uri2 == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let net1 = await instance.netFromUri(uri1)
    let net2 = await instance.netFromUri(uri2)
    let holder = await net1.bindTo(net2)
    let sref = await holder.castAs(Persistable).createSturdyRef(nullCap, persistent)
    echo sref.formatSturdyRef

dispatchGen(bindCmd)

proc main*() =
  dispatchSubcommand({
    "export": () => quit(dispatchExportCmd(argv, doc="")),
    "bind": () => quit(dispatchBindCmd(argv, doc=""))
  })
