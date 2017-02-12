import reactor, reactor/file, metac/stream, metac/instance, metac/schemas, metac/fs_util
import posix, collections

type
  LocalFile = ref object of RootObj
    instance: Instance
    path: string

proc open(self: LocalFile): Future[cint] =
  return openAt(self.path, finalFlags=O_RDONLY)

proc openAsStream(self: LocalFile): Future[schemas.Stream] {.async.} =
  let fd = (await self.open).FileFd
  let input = createInputFromFd(fd)
  return self.instance.wrapStream(BytePipe(input: input,
                                           output: nullOutput(byte)))

proc openAsBlock(self: LocalFile): Future[schemas.BlockDevice] {.async.} =
  return BlockDevice.createFromCap(nothingImplemented)

proc toCapServer(self: LocalFile): CapServer = return toGenericCapServer(self.asFile)

proc localFile*(instance: Instance, path: string): schemas.File =
  ## Return File cap for local file on path ``path``.
  return LocalFile(instance: instance, path: path).asFile

proc copyToTempFile*(instance: Instance, f: schemas.File, sizeLimit: int64=16 * 1024 * 1024): Future[string] {.async.} =
  ## Download file to a temporary local file. Return its path.
  let (inputFd, holder) = await instance.unwrapStream(await f.openAsStream)
  let path = "/tmp/metac_tmp_" & hexUrandom(16)
  let outputFd = await openAt(path, O_EXCL or O_CREAT or O_WRONLY)
  # TODO: defer: close(fd)
  let output = createOutputFromFd(outputFd.FileFd)
  let input = createInputFromFd(inputFd.FileFd)
  echo "piping file"
  await pipeLimited(input, output, sizeLimit)
  echo "got the file:", path
  return path
