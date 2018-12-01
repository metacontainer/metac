import xrest, metac/rest_common, metac/net

restRef FileRef:
  sctpStream("ndbConnection")
  sctpStream("data")

restRef FilesystemRef:
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
  sub("file", FileCollection) # internal
  sub("fs", FilesystemCollection) # internal
  sub("mounts", MountCollection)

  get() -> FilesystemNamespace
