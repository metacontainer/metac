import reactor, capnp, metac/instance, metac/schemas, metac/stream, metac/persistence, metac/cli_common, strutils, collections

proc fileFromUri[T: schemas.File|Filesystem](instance: Instance, uri: string, typ: typedesc[T]): Future[T] {.async.} =
  let s = uri.split(":", 1)
  let schema = s[0]
  let path = s[1]

  var root: Filesystem
  if schema == "local":
    let fsService = await instance.getServiceAdmin("fs", FilesystemServiceAdmin)
    let ns = await fsService.rootNamespace
    root = await ns.filesystem
  elif schema == "ref":
    return instance.restore(uri.parseSturdyRef).castAs(T)
  else:
    raise newException(ValueError, "invalid URI")

  when typ is schemas.File:
    return root.getFile(path)
  else:
    return root.getSubtree(path)

proc exportCmd() {.async.} =
  let instance = await newInstance()
  let uri = argv[0]
  let file = await instance.fileFromUri(uri, schemas.File)
  let sref = await file.castAs(schemas.Persistable).createSturdyRef(nullCap, true)
  echo sref.formatSturdyRef

proc catCmd() {.async.} =
  let instance = await newInstance()
  let uri = argv[0]
  let file = await instance.fileFromUri(uri, schemas.File)
  let stream = await file.openAsStream()
  let (fd, holder) = await instance.unwrapStreamAsPipe(stream)
  let data = await fd.input.readUntilEof()
  echo data

proc main*() =
  dispatchSubcommand({
    "export": () => exportCmd().runMain,
    "cat": () => catCmd().runMain
  })
