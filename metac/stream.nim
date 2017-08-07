import reactor, reactor/unix, caprpc, metac/instance, metac/schemas, collections, os, reactor/unix, posix, reactor/file

const bindfdPath* {.strdefine.} = "bindfd.so"

template unwrapStreamBase(instance, stream, connFunc): untyped =
  let boundSocket = await bindSocketForConnect(parseAddress(instance.address), 0)
  let localAddr = boundSocket.getSockAddr()

  let info = await stream.tcpListen(
    remote=instance.nodeAddress,
    port=localAddr.port.int32
  )
  if info.local.ip == nil: raise newException(ValueError, "bad address")

  let fd = await connFunc(TcpConnectionData(
    host: parseAddress(info.local.ip),
    port: info.port,
    boundSocket: boundSocket))

  (fd, info.holder)

proc unwrapStream*(instance: Instance, stream: schemas.Stream): Future[tuple[fd: cint, holder: Holder]] {.async.} =
  ## Turns (possibly remote) Stream into a file descriptor.
  return unwrapStreamBase(instance, stream, connectTcpAsFd)

proc unwrapStreamAsPipe*(instance: Instance, stream: schemas.Stream): Future[BytePipe] {.async.} =
  ## Turn (possibly remote) Stream into a local BytePipe.
  let (pipe, holder) = unwrapStreamBase(instance, stream, connectTcp)

  type PipeAndHolder = ref object of BytePipe
    holder: Holder

  return PipeAndHolder(input: pipe.input, output: pipe.output, holder: holder)

proc streamTrace(args: varargs[string, `$`]) =
  when defined(metacTraceStreams):
    stderr.writeLine args

proc wrapStream*(instance: Instance, getStream: (proc(): Future[BytePipe])): schemas.Stream =
  proc acceptConnections(remote: schemas.NodeAddress, port: int32, server: TcpServer): Future[void] {.async.} =
    asyncFor conn in server.incomingConnections:
      let address = conn.getPeerAddr
      streamTrace "stream: connection from ", address
      if address.address != parseAddress(remote.ip) or address.port != port:
        streamTrace "stream: invalid host attempted connection (host: [$1]:$2, expected: [$3]:$4)" % [
          $address.address, $address.port, $parseAddress(remote.ip), $port]
        conn.close(JustClose)
        continue

      defer:
        streamTrace("stream: connection finished (", address, ")")
      server.incomingConnections.recvClose(JustClose)
      let streamPipe = await getStream()
      let res = tryAwait pipe(conn.BytePipe, streamPipe)
      if res.isError:
        streamTrace("stream: piping finished with error ", res)
      else:
        streamTrace("stream: piping finished")
      return

  proc tcpListenImpl(remote: schemas.NodeAddress, port: int32): Future[Stream_tcpListen_Result] {.async.} =
    # FIXME: leak when someone abandons their request
    let server = await createTcpServer(0, host=instance.address)
    let servAddr = server.getSockAddr

    acceptConnections(remote, port, server).ignore

    return Stream_tcpListen_Result(
      local: instance.nodeAddress,
      port: servAddr.port.int32,
      holder: holder[void]())

  proc bindToImpl(other: Stream): Future[Holder] {.async.} =
    # TODO: leak (return correct holder)

    let thisPipe = await getStream()
    let otherPipe = await instance.unwrapStreamAsPipe(other)
    await pipe(otherPipe, thisPipe)

    return nullCap

  let cap = schemas.Stream.inlineCap(StreamInlineImpl(tcpListen: tcpListenImpl, bindTo: bindToImpl))
  return cap

proc wrapStream*(instance: Instance, stream: BytePipe): schemas.Stream =
  # TODO: if there is more than one connection, things break
  return wrapStream(instance, () => now(just(stream)))

proc wrapStreamFd*(instance: Instance, stream: cint): schemas.Stream =
  ## Wrap a file descriptor. Do not close it, it will be closed automatically.
  return wrapStream(instance, streamFromFd(stream))

proc newStreamPair*(instance: Instance): tuple[a: Stream, b: Stream] =
  let (a, b) = newPipe(byte)
  return (wrapStream(instance, a), wrapStream(instance, b))

proc wrapUnixSocketAsStream*(instance: Instance, path: string): schemas.Stream =
  var buf: Stat
  assert stat(path.cstring, buf) == 0, "socket doesn't exist"

  return wrapStream(instance, () => connectUnix(path).then(x => x.BytePipe))

proc makeUnixAddr(path: string): Sockaddr_un =
    result.sun_family = AF_UNIX
    if path.len >= Sockaddr_un_path_length:
      raise newException(ValueError, "socket path too long")
    copyMem(addr result.sun_path, path.cstring, path.len + 1)

proc mkdtemp(tmpl: cstring): cstring {.importc, header: "stdlib.h".}

proc createUnixSocketDir*(): tuple[path: string, cleanup: proc()] =
  var dirPath = "/tmp/metac_unix_XXXXXXXX"
  if mkdtemp(dirPath) == nil:
    raiseOSError(osLastError())

  proc finish() =
    removeFile(dirPath & "/socket")
    removeDir(dirPath)

  return (dirPath, finish)

proc wrapUnixServerFdAsStream*(instance: Instance): tuple[serverFd: cint, stream: schemas.Stream, cleanup: proc()] =
  let (path, cleanup) = createUnixSocketDir()
  let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
  var sockAddr = makeUnixAddr(path & "/socket")
  if bindSocket(serverFd, cast[ptr SockAddr](addr sockAddr), sizeof(sockAddr).Socklen) != 0:
    discard close(serverFd)
    cleanup()
    raiseOSError(osLastError())

  if listen(serverFd, SOMAXCONN) != 0:
    discard close(serverFd)
    cleanup()
    raiseOSError(osLastError())

  return (serverFd.cint, wrapUnixSocketAsStream(instance, path & "/socket"), cleanup)

proc unwrapStreamToUnixSocket*(instance: Instance, stream: schemas.Stream): Future[string] =
  let (dirPath, cleanup) = createUnixSocketDir()
  let path = dirPath & "/socket"
  let server = createUnixServer(path)

  proc handler(): Future[void] {.async.} =
    defer:
      cleanup()
      server.incomingConnections.recvClose JustClose

    let conn = await server.incomingConnections.receive
    let unwrappedStream = await instance.unwrapStreamAsPipe(stream)
    await pipe(conn.BytePipe, unwrappedStream)

  handler().ignore
  return now(just(path))
