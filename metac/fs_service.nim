import xrest, metac/fs, strutils, metac/service_common, metac/rest_common, metac/flatdb, metac/fs_impl, metac/flatdb, collections, reactor, posix

{.reorder: on.}

type
  MountHandler = ref object
    info: Mount
    process: reactor.Process

  FilesystemService = ref object
    mountDb: FlatDB
    mounts: Table[string, MountHandler]

proc decodePath(path: string): string =
  result = urlDecode(path)
  assert result[0] == '/'

proc `file/item/*`(s: FilesystemService, encodedPath: string): FileImpl =
  return FileImpl(path: decodePath(encodedPath))

proc `fs/item/*`(s: FilesystemService, encodedPath: string): FsImpl =
  return FsImpl(path: decodePath(encodedPath))

proc doMount(m: Mount) {.async.} =
  if m.blockDev.isSome:
    await doMountBlock(m.blockDev.get, m.path)
  else:
    await doMount(m.fs.get, m.path)

proc startMounter(s: FilesystemService, id: string) {.async.} =
  var waitTime = 1000
  # let handler = s.mounts[id]

  while true:
    if id notin s.mountDb: break

    let info = await dbFromJson(s.mountDb[id], Mount)

    let r = tryAwait doMount(info)
    if r.isError: r.error.printError
    waitTime *= 2; waitTime = min(waitTime, 10000)

proc `mounts/get`(s: FilesystemService): Future[seq[MountRef]] {.async.} =
  return toSeq(s.mountDb.keys).mapIt(makeRef(MountRef, it))

proc `mounts/create`(s: FilesystemService, mount: Mount): Future[MountRef] {.async.} =
  if mount.fs.isSome == mount.blockDev.isSome:
    raise newException(Exception, "create mount: either fs or blockDev should be given")

  if mount.blockDev.isSome and getuid() != 0:
    raise newException(Exception, "block device mounts are supported only for root user")

  let id = hexUrandom()
  let handler = MountHandler(info: mount)
  s.mounts[id] = handler
  s.mountDb[id] = toJson(mount)

  startMounter(s, id).ignore

proc `mounts/item/get`(s: FilesystemService, id: string): Future[Mount] {.async.} =
  return s.mounts[id].info

proc `mounts/item/delete`(s: FilesystemService, id: string): Future[void] {.async.} =
  discard

proc `mounts/item/update`(s: FilesystemService, id: string, info: Mount): Future[void] {.async.} =
  discard

proc `get`(s: FilesystemService): FilesystemNamespace =
  return FilesystemNamespace(
    rootFs: makeRef(FilesystemRef, "fs/" & encodePath("/")),
  )

proc main*() {.async.} =
  let s = FilesystemService(
    mountDb: makeFlatDB(getConfigDir() / "metac" / "mounts"),
    mounts: initTable[string, MountHandler]()
  )
  let handler = restHandler(FilesystemNamespaceRef, s)

  for id in s.mountDb.keys:
    s.mounts[id] = MountHandler()
    startMounter(s, id).ignore

  await runService("fs", handler)

when isMainModule:
  main().runMain
