# included from metac/fs.nim

type
  LocalNamespace = ref object of PersistableObj
    instance: ServiceInstance

  LocalFsMount = ref object of PersistableObj
    v9fsStreamHolder: Holder
    path: string
    fs: Filesystem
    onFinish: Future[void]

proc info(m: LocalFsMount): Future[string] {.async.} =
  return m.path

proc wait(m: LocalFsMount): Future[void] {.async.} =
  await m.onFinish

capServerImpl(LocalFsMount, [Mount, Persistable, Waitable])

proc filesystem(ns: LocalNamespace): Future[Filesystem] {.async.} =
  return localFsPersistable(ns.instance, "/")

proc mount(ns: LocalNamespace, path: string, fs: Filesystem): Future[Mount] {.async.}
proc listMounts(ns: LocalNamespace): Future[seq[Mount]] {.async.}

capServerImpl(LocalNamespace, [FilesystemNamespace, Persistable, Waitable])

proc mount*(instance: Instance, path: string, fs: Filesystem): Future[tuple[holder: Holder, onFinish: Future[void]]] {.async.} =
  let stream = await fs.v9fsStream
  let (fd, holder) = await instance.unwrapStream(stream)

  echo "unmounting old filesystem at ", path
  discard (tryAwait execCmd(@["umount", "-l", "/" & path]))

  echo "mounting..."

  var flags = fcntl(fd.cint, F_GETFL, 0)
  if flags == -1:
    raiseOSError(osLastError())
  discard fcntl(fd.cint, F_SETFL, flags or (O_NONBLOCK))

  # "cache=loose" forces 9p to send page-sized requests serially, which is SLOW for serial reads!
  # In future we will want to write FUSE client that does intelligent read ahead. Or use NFS. Or SSHFS.
  let process = startProcess(@["mount", "-t", "9p", "-o", "trans=fd,rfdno=4,wfdno=4,uname=root,msize=131144,aname=/,access=client,cache=mmap", "metacfs", "/" & path],
                             additionalFiles= @[(4.cint, fd.cint), (0.cint, 0.cint), (1.cint, 1.cint), (2.cint, 2.cint)])

  let onFinish = newCompleter[void]()

  proc closed() =
    echo "9p connection closed"
    discard close(fd)
    onFinish.completeError("disconnected")

  waitForFdError(fd).then(closed).ignore

  return (holder, onFinish.getFuture)

proc mount(ns: LocalNamespace, path: string, fs: Filesystem): Future[Mount] {.async.} =
  let (holder, onFinish) = await mount(ns.instance, path, fs)

  return LocalFsMount(
    v9fsStreamHolder: holder,
    onFinish: onFinish,
    path: path,
    fs: fs,
    persistenceDelegate: makePersistenceDelegate(ns.instance, "fs:mount",
                                                 FilesystemNamespace_mount_Params(path: path, fs: fs).toAnyPointer)
  ).asMount

proc listMounts(ns: LocalNamespace): Future[seq[Mount]] {.async.} =
  return newSeq[Mount]()
