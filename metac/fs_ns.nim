# included from metac/fs.nim

type
  LocalNamespace = ref object of PersistableObj
    instance: ServiceInstance

  LocalFsMount = ref object of PersistableObj
    v9fsStreamHolder: Holder
    path: string
    fs: Filesystem

proc info(m: LocalFsMount): Future[string] {.async.} =
  return m.path

capServerImpl(LocalFsMount, [Mount, Persistable])

proc filesystem(ns: LocalNamespace): Future[Filesystem] {.async.} =
  return localFsPersistable(ns.instance, "/")

proc mount(ns: LocalNamespace, path: string, fs: Filesystem): Future[Mount] {.async.}
proc listMounts(ns: LocalNamespace): Future[seq[Mount]] {.async.}

capServerImpl(LocalNamespace, [FilesystemNamespace, Persistable])

proc mount(ns: LocalNamespace, path: string, fs: Filesystem): Future[Mount] {.async.} =
  let stream = await fs.v9fsStream
  let (fd, holder) = await ns.instance.unwrapStream(stream)

  var buf: Stat
  if stat(path, buf) != 0 and errno == posix.EIO:
    echo "unmounting old filesystem at ", path
    await execCmd(@["umount", "-l", "/" & path])

  echo "mounting..."
  let process = startProcess(@["mount", "-t", "9p", "-o", "trans=fd,rfdno=4,wfdno=4,uname=root,aname=/,access=client", "none", "/" & path],
                             additionalFiles= @[(4.cint, fd.cint), (2.cint, 2.cint)])

  return LocalFsMount(
    v9fsStreamHolder: holder,
    path: path,
    fs: fs,
    persistenceDelegate: makePersistenceDelegate(ns.instance, "fs:mount",
                                                 FilesystemNamespace_mount_Params(path: path, fs: fs).toAnyPointer)
  ).asMount

proc listMounts(ns: LocalNamespace): Future[seq[Mount]] {.async.} =
  return newSeq[Mount]()
