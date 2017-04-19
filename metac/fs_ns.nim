# included from metac/fs.nim

type
  LocalNamespace = ref object of RootObj
    instance: Instance

  LocalMount = ref object of RootObj

  
proc filesystem(ns: LocalNamespace): Future[Filesystem] =
  return now(just(LocalFilesystem(path: "/", instance: ns.instance).asFilesystem))

proc mount(ns: LocalNamespace, path: string, fs: Filesystem): Future[Mount] {.async.} =
  discard

proc listMounts(ns: LocalNamespace): Future[seq[Mount]] {.async.} =
  return newSeq[Mount]()

capServerImpl(LocalNamespace, FilesystemNamespace)
