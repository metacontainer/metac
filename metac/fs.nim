import xrest, metac/rest_common, metac/net, strutils, collections

type
  Filesystem* = object
    path*: string

  FileEntry* = object
    name*: string
    isDirectory*: bool

  FsListing* = object
    isAccessible*: bool
    entries*: seq[FileEntry]

  File* = object
    path*: string

restRef FileRef:
  sctpStream("nbdConnection")
  sctpStream("data")

restRef FilesystemRef:
  get() -> Filesystem
  call("listing") -> FsListing
  rawRequest("sub")
  sctpStream("sftpConnection")

restRef FileCollection:
  collection(FileRef)

restRef FilesystemCollection:
  collection(FilesystemRef)

type FilesystemNamespace* = object
  rootFs*: FilesystemRef

type BlockDevMount* = object
  dev*: FileRef
  offset*: int

type Mount* = object
  path*: string
  persistent*: bool
  readonly*: bool

  fs*: Option[FilesystemRef]
  blockDev*: Option[BlockDevMount]

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
