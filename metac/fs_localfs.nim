# included from metac/fs.nim

type LocalFilesystem = ref object of RootObj
  instance: Instance
  path: string

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem]
proc v9fsStream(fs: LocalFilesystem): Future[Stream]
proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File]

capServerImpl(LocalFilesystem, Filesystem)

proc getSubtree(fs: LocalFilesystem, path: string): Future[Filesystem] =
  return now(just(
    LocalFilesystem(instance: fs.instance, path: safeJoin(fs.path, path)).asFilesystem))

proc getFile(fs: LocalFilesystem, path: string): Future[schemas.File] =
  return now(just(
    LocalFile(instance: fs.instance, path: safeJoin(fs.path, path)).asFile))

async:
 proc v9fsStream(fs: LocalFilesystem): Future[Stream] =
  const diodPath = "third-party/diod/diod/diod"

  # TODO: run diod directly on the TCP connection

  var rdPipe: array[2, cint]
  if posix.pipe(rdPipe) != 0:
    raiseOSError(osLastError())

  var wrPipe: array[2, cint]
  if posix.pipe(wrPipe) != 0:
    raiseOSError(osLastError())

  let v9fsPipe = BytePipe(input: createInputFromFd(rdPipe[0].FileFd),
                          output: createOutputFromFd(wrPipe[1].FileFd))

  return fs.instance.wrapStream(v9fsPipe)
