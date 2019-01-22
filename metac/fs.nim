import xrest, metac/rest_common, metac/net, strutils

type
  Filesystem* = object
    path*: string

  File* = object
    path*: string

restRef FileRef:
  sctpStream("nbdConnection")
  sctpStream("data")

restRef FilesystemRef:
  get() -> Filesystem
  sctpStream("sftpConnection")

restRef FileCollection:
  collection(FileRef)

restRef FilesystemCollection:
  collection(FilesystemRef)

type FilesystemNamespace* = object
  rootFs*: FilesystemRef

type Mount* = object
  path*: string
  fs*: FilesystemRef
  persistent*: bool

restRef MountRef:
  get() -> Mount
  update(Mount)
  delete()

basicCollection(Mount, MountRef)

restRef FilesystemNamespaceRef:
  sub("file", FileCollection)
  sub("fs", FilesystemCollection)
  sub("mounts", MountCollection)

  get() -> FilesystemNamespace

proc encodePath*(path: string): string =
  assert path[0] == '/'
  return urlEncode(path)
