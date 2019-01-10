import metac/service_common, metac/rest_common, metac/net, reactor, reactor/unix, metac/os_fs, posix

proc makeUnixSocket*(s: SctpConn): tuple[path: string, cleanup: proc()] =
  # create unix socket that
  let (path, sockCleanup) = createUnixSocketDir()

  let server = createUnixServer(path)

  proc cleanup() =
    sockCleanup()
    server.incomingConnections.recvClose

  server.incomingConnections.receive.then(
    proc(conn: UnixConnection): Future[void] =
      return pipe(s, BytePipe(conn))
  ).ignore

  return (path, cleanup)

proc copyToTemp*(s: ByteStream, maxLength=100 * 1024 * 1024): Future[tuple[path: string, cleanup: proc()]] {.async.} =

  let dirPath = makeTempDir()

  proc cleanup() =
    removeDir(dirPath)

  let filePath = dirPath / "data"
  let stream: SctpConn = await s.data()
  let fd = posix.open(filePath, O_WRONLY or O_CREAT, 0o666)
  let file = createOutputFromFd(fd)

  defer:
    file.sendClose

  let r = tryAwait pipe(stream, file)
  if not r.isSuccess:
    cleanup()
    await r

  return (dirPath, cleanup)
