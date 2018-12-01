import xrest, metac/fs, strutils, metac/service_common, metac/rest_common, metac/flatdb, metac/fs_impl

type
  MountHandler = ref object
    info: Mount

  FilesystemService = ref object
    mountDb: FlatDB
    mounts: seq[MountHandler]

proc encodePath(path: string): string =
  assert path[0] == '/'
  for ch in path:
    if ch in Digits or ch in Letters:
      result &= ch
    else:
      result &= "=" & toHex(int(ch), 2)

proc decodePath(path: string): string =
  var i = 0
  while i < len(path):
    if path[i] == '=':
      assert i + 2 < len(path)
      result &= parseHexInt("0x" & path[i+1..i+3])
      i += 3
    else:
      assert path[i] in Digits or path[i] in Letters
      result &= path[i]
      i += 1

proc `file/item`(s: FilesystemService, encodedPath: string): FileImpl =
  return FileImpl(path: decodePath(encodedPath))

proc `fs/item`(s: FilesystemService, encodedPath: string): FsImpl =
  return FsImpl(path: decodePath(encodedPath))

proc `mounts/get`(s: FilesystemService): Future[seq[MountRef]] {.async.} =
  discard

proc `mounts/item/get`(s: FilesystemService, id: string): Future[Mount] {.async.} =
  return toSeq(s.mountDb.keys).mapIt(makeRef(MountRef, id))

proc `mounts/item/delete`(s: FilesystemService, id: string): Future[void] {.async.} =
  discard

proc `mounts/item/update`(s: FilesystemService, id: string, info: Mount): Future[void] {.async.} =
  discard

proc `get`(s: FilesystemService): FilesystemNamespace =
  return FilesystemNamespace(
    rootFs: makeRef(FilesystemRef, "fs/" & encodePath("/")),
  )

proc main() {.async.} =
  let s = FilesystemService(
    mountDb: makeFlatDB(getConfigDir() / "metac" / "mounts")
  )
  let handler = restHandler(FilesystemNamespaceRef, s)
  await runService("fs", handler)

when isMainModule:
  main().runMain
