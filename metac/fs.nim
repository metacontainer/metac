import xrest, metac/restcommon

restRef FileRef:
  sctpStream("ndbConnection")

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

restRef MountRef:
  get() -> Mount
  update(Mount)
  delete()

restRef MountCollection:
  collection(MountRef)
  get() -> seq[MountRef]

restRef FilesystemNamespaceRef:
  sub("file", FileCollection) # internal
  sub("fs", FilesystemCollection) # internal
  sub("mounts", MountCollection)

  get() -> FilesystemNamespace
