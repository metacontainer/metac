# included from metac/fs.nim

proc copyToTempFile*(instance: Instance, f: schemas.File, sizeLimit: int64=16 * 1024 * 1024): Future[string] {.async.} =
  ## Download file to a temporary local file. Return its path. You should unlink it when you are done with it.
  let (inputFd, holder) = await instance.unwrapStream(await f.openAsStream)
  let path = "/tmp/metac_tmp_" & hexUrandom(16)
  let outputFd = await openAt(path, O_EXCL or O_CREAT or O_WRONLY)
  defer: discard close(outputFd)
  let output = createOutputFromFd(outputFd.FileFd)
  let input = createInputFromFd(inputFd.FileFd)
  await pipeLimited(input, output, sizeLimit)
  return path
