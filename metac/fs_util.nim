# included from metac/fs.nim

proc copyToTempFile*(instance: Instance, f: schemas.File, sizeLimit: int64=16 * 1024 * 1024): Future[string] {.async.} =
  ## Download file to a temporary local file. Return its path. You should unlink it when you are done with it.
  let stream = await f.openAsStream
  let (inputFd, holder) = await instance.unwrapStream(stream)
  let path = "/tmp/metac_tmp_" & hexUrandom(16)
  let outputFd = await openAt(path, O_EXCL or O_CREAT or O_WRONLY)
  let output = createOutputFromFd(outputFd)
  let input = createInputFromFd(inputFd)
  await pipeLimited(input, output, sizeLimit)
  fakeUsage(holder)
  return path
