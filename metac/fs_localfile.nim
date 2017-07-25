# included from metac/fs.nim

type
  LocalFile = ref object of PersistableObj
    instance: Instance
    path: string

# LocalFile

proc open(self: LocalFile): Future[cint] =
  return openAt(self.path, finalFlags=O_RDONLY)

proc openAsStream(self: LocalFile): Future[schemas.Stream] {.async.} =
  let fd = (await self.open).FileFd
  let input = createInputFromFd(fd)
  return self.instance.wrapStream(BytePipe(input: input,
                                           output: nullOutput(byte)))

proc nbdSetup(self: LocalFile): Future[schemas.Stream] {.async.} =
  let fd = (await self.open)
  setBlocking(fd.FileFd)

  let files = @[(1.cint, 1.cint), (2.cint, 2.cint), (3.cint, fd)]
  let (dirPath, cleanup) = createUnixSocketDir()
  # TODO: defer: cleanup()
  let socketPath = dirPath & "/socket"
  startProcess(@["qemu-nbd",
                 "-f", "raw",
                 "/proc/self/fd/3", "--socket=" & socketPath],
               additionalFiles=files).detach

  await waitForFile(socketPath)

  return wrapUnixSocketAsStream(self.instance, socketPath)

proc openAsBlock(self: LocalFile): Future[schemas.BlockDevice] {.async.}

capServerImpl(LocalFile, [schemas.File, BlockDevice, Persistable, Waitable])

proc openAsBlock(self: LocalFile): Future[schemas.BlockDevice] {.async.} =
  return self.asBlockDevice

# LocalFileBlockDev

proc localFile*(instance: Instance, path: string, persistenceDelegate: PersistenceDelegate=nil): schemas.File =
  ## Return File cap for local file on path ``path``.
  return LocalFile(instance: instance, path: path, persistenceDelegate: persistenceDelegate).asFile

proc localFilePersistable(instance: ServiceInstance, path: string, runtimeId: string=nil): schemas.File =
  return localFile(instance, path, instance.makePersistenceDelegate(
    category="fs:localfile", description=toAnyPointer(path), runtimeId=runtimeId))
