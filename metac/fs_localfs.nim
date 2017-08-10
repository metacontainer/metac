# included from metac/fs.nim

type
  LocalFilesystem = ref object of PersistableObj
    instance: ServiceInstance
    path: string

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem] {.async.}
proc v9fsStream(fs: LocalFilesystem): Future[Stream] {.async.}
proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File] {.async.}
proc summary(fs: LocalFilesystem): Future[string] {.async.} = return fs.path
proc readonlyFs(fs: LocalFilesystem): Future[schemas.Filesystem] {.async.}
proc sftpStream(fs: LocalFilesystem): Future[Stream] {.async.}

capServerImpl(LocalFilesystem, [Filesystem, Persistable, Waitable])

proc localFs*(instance: ServiceInstance, path: string, persistenceDelegate: PersistenceDelegate=nil): schemas.Filesystem =
  ## Return Filesystem cap for local filesystem on path ``path``.
  return LocalFilesystem(instance: instance, path: path, persistenceDelegate: persistenceDelegate).asFilesystem

proc localFsPersistable(instance: ServiceInstance, path: string): schemas.Filesystem =
  return localFs(instance, path, instance.makePersistenceDelegate(
    category="fs:localfs", description=toAnyPointer(path)))

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem] {.async.} =
  if fs.path == "/":
    return localFsPersistable(fs.instance, safeJoin("/", path))
  else:
    return localFs(fs.instance, safeJoin(fs.path, path),
                   makePersistenceCallDelegate(fs.instance, fs.asFilesystem, Filesystem_getSubtree_Params(name: path)))

proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File] {.async.} =
  if fs.path == "/":
    return localFilePersistable(fs.instance, path)
  else:
    return localFile(fs.instance, safeJoin(fs.path, path),
                     makePersistenceCallDelegate(fs.instance, fs.asFilesystem, Filesystem_getFile_Params(name: path)))

proc readonlyFs(fs: LocalFilesystem): Future[schemas.Filesystem] {.async.} =
  asyncRaise "not implemented"

const diodPath {.strdefine.} = "metac-diod"
const sftpServerPath {.strdefine.} = "metac-sftp-server"

proc v9fsStream(fs: LocalFilesystem): Future[Stream] {.async.} =
  # TODO: run diod directly on the TCP connection
  echo "starting diod... (path: $1)" % fs.path

  let dirFd = await openAt(fs.path)
  defer: discard close(dirFd)

  let process = startProcess(@[getAppDir() / diodPath, "--foreground", "--no-auth", "--logdest", "stderr", "--rfdno", "4", "--wfdno", "4", "--export", "/", "-c", "/dev/null", "--chroot-to", "3", "--no-userdb"],
                             pipeFiles = [4.cint],
                             additionalFiles = [(3.cint, dirFd.cint),
                                                (0.cint, 2.cint), (1.cint, 2.cint), (2.cint, 2.cint)])

  process.wait.then(proc(status: int) = echo("diod exited with code ", status)).ignore

  let v9fsPipe = BytePipe(input: process.files[0].input,
                          output: process.files[0].output)

  return fs.instance.wrapStream(v9fsPipe)

proc sftpStream(fs: LocalFilesystem): Future[Stream] {.async.} =
  # TODO: run directly on the TCP connection
  echo "starting SFTP server... (path: $1)" % fs.path

  var pair: array[0..1, cint]
  if socketpair(AF_UNIX, SOCK_STREAM or SOCK_CLOEXEC, 0, pair) != 0:
    asyncRaise "socketpair call failed"

  let fd = pair[0]
  defer: discard (close fd)

  let pipe = streamFromFd(pair[1])
  let dirFd = await openAt(fs.path)
  defer: discard close(dirFd)

  let process = startProcess(@[getAppDir() / sftpServerPath,
                                "-e", # stderr instead of syslog
                                "-C", "4", # chroot to
                                #"-l", "DEBUG3",
                             ],
                             additionalFiles= [(0.cint, fd.cint), (1.cint, fd.cint), (2.cint, 2.cint), (4.cint, dirFd.cint)])

  process.wait.then(proc(status: int) = echo("SFTP server exited with code ", status)).ignore

  return fs.instance.wrapStream(pipe)
