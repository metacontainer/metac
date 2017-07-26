import reactor, capnp, metac/instance, metac/schemas, metac/stream, metac/persistence, metac/cli_common, strutils, collections, cligen

proc fileFromUri*[T: schemas.File|Filesystem](instance: Instance, uri: string, typ: typedesc[T]): Future[T] {.async.} =
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

proc fileFromUri*(instance: Instance, uri: string): auto = return fileFromUri(instance, uri, schemas.File)
proc fsFromUri*(instance: Instance, uri: string): auto = return fileFromUri(instance, uri, schemas.Filesystem)

defineExporter(fsExportCmd, fsFromUri)
defineExporter(fileExportCmd, fileFromUri)

proc catCmd(uri: string) =
  if uri == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let file = await instance.fileFromUri(uri, schemas.File)
    let stream = await file.openAsStream()
    let fd = await instance.unwrapStreamAsPipe(stream)
    let data = await fd.input.readUntilEof()
    echo data

dispatchGen(catCmd)

proc mountCmd(uri: string, path: string, persistent=false) =
  if uri == nil or path == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let fs = await instance.fileFromUri(uri, schemas.Filesystem)
    let fsService = await instance.getServiceAdmin("fs", FilesystemServiceAdmin)
    let mnt = await fsService.rootNamespace.mount(path, fs)

    let sref = await mnt.castAs(schemas.Persistable).createSturdyRef(nullCap, persistent)
    echo sref.formatSturdyRef

dispatchGen(mountCmd)

proc openCmd(uri: string, persistent=false) =
  if uri == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let file = await instance.fileFromUri(uri, schemas.File)
    let stream = await file.openAsStream()

    let sref = await stream.castAs(schemas.Persistable).createSturdyRef(nullCap, persistent)
    echo sref.formatSturdyRef

dispatchGen(openCmd)

proc mainFile*() =
  dispatchSubcommand({
    "export": () => quit(dispatchFileExportCmd(argv, doc="")),
    "cat": () => quit(dispatchCatCmd(argv, doc="Print the file content to the standard output.")),
    "open": () => quit(dispatchCatCmd(argv, doc="Turn a file into a stream.")),
  })

proc mainFs*() =
  dispatchSubcommand({
    "export": () => quit(dispatchFsExportCmd(argv, doc="")),
    "mount": () => quit(dispatchMountCmd(argv, doc=""))
  })
