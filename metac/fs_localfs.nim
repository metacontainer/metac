# included from metac/fs.nim

type
  LocalFilesystem = ref object of PersistableObj
    instance: ServiceInstance
    path: string

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem]
proc v9fsStream(fs: LocalFilesystem): Future[Stream] {.async.}
proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File]

capServerImpl(LocalFilesystem, Filesystem)

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem] =
  return now(just(
    LocalFilesystem(instance: fs.instance, path: safeJoin(fs.path, path)).asFilesystem))

proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File] =
  return now(just(
    localFilePersistable(fs.instance, safeJoin(fs.path, path))))

proc v9fsStream(fs: LocalFilesystem): Future[Stream] {.async.} =
  const diodPath = "build/diod-server"

  # TODO: run diod directly on the TCP connection
  # TODO: run in chroot (prevent symlink attacks) -- need to modify diod server

  echo "starting diod..."

  let dirFd = await openAt(fs.path)
  defer: discard close(dirFd)

  let process = startProcess(@[diodPath, "--foreground", "--no-auth", "--logdest", "stderr", "--rfdno", "4", "--wfdno", "4", "--export", "/", "-c", "/dev/null", "--chroot-to", "3", "--no-userdb"],
                             pipeFiles = [4.cint],
                             additionalFiles= [(3.cint, dirFd.cint)])

  let v9fsPipe = BytePipe(input: process.files[0].input,
                          output: process.files[0].output)

  return fs.instance.wrapStream(v9fsPipe)
