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

const sshfsPath {.strdefine.} = "metac-sshfs"

proc mount*(instance: Instance, path: string, fs: Filesystem): Future[tuple[holder: Holder, onFinish: Future[void]]] {.async.} =
  echo "unmounting old filesystem at ", path
  discard (tryAwait execCmd(@["umount", "-l", "/" & path]))

  when not defined(use9pForMounts):
    let stream = await fs.sftpStream
    let (fd, holder) = await instance.unwrapStream(stream)

    let process = startProcess(@[getAppDir() / sshfsPath,
                                 "-f", # foreground
                                 "-o", "allow_other,default_permissions",
                                 "-o", "ssh_command=/proc/$1/exe sshfs-mount-helper" % [$getpid()],
                                 "metacfs:", "/" & path],
                               additionalFiles= @[(4.cint, fd.cint), (0.cint, 0.cint), (1.cint, 1.cint), (2.cint, 2.cint)])
    discard close(fd)

    let onFinish = newCompleter[void]()

    proc closed(code: int) =
      echo "SSHFS connection closed"
      onFinish.completeError("disconnected")

    process.wait.then(closed).ignore
    return (holder, onFinish.getFuture)
  else:
    let stream = await fs.v9fsStream
    let (fd, holder) = await instance.unwrapStream(stream)
    echo "mounting..."

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

proc sshfsMountHelper*() {.async.} =
  let socket = streamFromFd(4)
  let stdin = streamFromFd(0)

  await pipe(stdin, socket)

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
