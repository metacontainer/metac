# included from metac/fs.nim

type
  LocalFilesystem = ref object of PersistableObj
    instance: ServiceInstance
    path: string

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem] {.async.}
proc v9fsStream(fs: LocalFilesystem): Future[Stream] {.async.}
proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File] {.async.}

capServerImpl(LocalFilesystem, [Filesystem, Persistable])

proc localFs*(instance: ServiceInstance, path: string, persistenceDelegate: PersistenceDelegate=nil): schemas.Filesystem =
  ## Return Filesystem cap for local filesystem on path ``path``.
  return LocalFilesystem(instance: instance, path: path, persistenceDelegate: persistenceDelegate).asFilesystem

proc localFsPersistable(instance: ServiceInstance, path: string): schemas.Filesystem =
  return localFs(instance, path, instance.makePersistenceDelegate(
    category="fs:localfs", description=toAnyPointer(path)))

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem] {.async.} =
  return localFs(fs.instance, safeJoin(fs.path, path),
                 makePersistenceCallDelegate(fs.instance, fs.asFilesystem, Filesystem_getSubtree_Params(name: path)))

proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File] {.async.} =
  return localFile(fs.instance, safeJoin(fs.path, path),
                   makePersistenceCallDelegate(fs.instance, fs.asFilesystem, Filesystem_getFile_Params(name: path)))

const diodPath {.strdefine.} = "build/diod-server"

proc v9fsStream(fs: LocalFilesystem): Future[Stream] {.async.} =
  # TODO: run diod directly on the TCP connection
  echo "starting diod... (path: $1)" % fs.path

  let dirFd = await openAt(fs.path)
  defer: discard close(dirFd)

  let process = startProcess(@[diodPath, "--foreground", "--no-auth", "--logdest", "stderr", "--rfdno", "4", "--wfdno", "4", "--export", "/", "-c", "/dev/null", "--chroot-to", "3", "--no-userdb"],
                             pipeFiles = [4.cint],
                             additionalFiles = [(3.cint, dirFd.cint),
                                                (0.cint, 2.cint), (1.cint, 2.cint), (2.cint, 2.cint)])

  process.wait.then(proc(status: int) = echo("diod exited with code ", status)).ignore

  let v9fsPipe = BytePipe(input: process.files[0].input,
                          output: process.files[0].output)

  return fs.instance.wrapStream(v9fsPipe)
