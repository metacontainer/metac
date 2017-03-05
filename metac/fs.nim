import reactor, reactor/file, reactor/process
import metac/stream, metac/instance, metac/schemas, metac/fs_util
import posix, collections, os

type
  LocalFile = ref object of RootObj
    instance: Instance
    path: string

  LocalFileBlockDev = ref object of RootObj
    localFile: LocalFile

proc open(self: LocalFile): Future[cint] =
  return openAt(self.path, finalFlags=O_RDONLY)

proc openAsStream(self: LocalFile): Future[schemas.Stream] {.async.} =
  let fd = (await self.open).FileFd
  let input = createInputFromFd(fd)
  return self.instance.wrapStream(BytePipe(input: input,
                                           output: nullOutput(byte)))

proc nbdSetup(blockDev: LocalFileBlockDev): Future[schemas.Stream] {.async.} =
  let self = blockDev.localFile
  let fd = (await self.open)
  setBlocking(fd.FileFd)

  let files = @[(1.cint, 1.cint), (2.cint, 2.cint), (3.cint, fd)]
  let socketPath = "/run/metac/nbd_socket_" & hexUrandom(16)
  startProcess(@["qemu-nbd",
                 "-f", "raw",
                 "/proc/self/fd/3", "--socket=" & socketPath],
               additionalFiles=files).detach

  var buf: Stat
  while stat(socketPath.cstring, buf) != 0:
    await asyncSleep(10)

  return wrapUnixSocketAsStream(self.instance, socketPath)

proc toCapServer(self: LocalFileBlockDev): CapServer = return toGenericCapServer(self.asBlockDevice)

proc openAsBlock(self: LocalFile): Future[schemas.BlockDevice] {.async.} =
  return LocalFileBlockDev(localFile: self).asBlockDevice

proc toCapServer(self: LocalFile): CapServer = return toGenericCapServer(self.asFile)

proc localBlockDevice*(instance: Instance, path: string): schemas.BlockDevice =
  ## Return BlockDevice cap for local file on path ``path``.
  return LocalFileBlockDev(localFile: LocalFile(instance: instance, path: path)).asBlockDevice

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
  await pipeLimited(input, output, sizeLimit)
  return path
