import reactor, caprpc, metac/instance, metac/schemas, collections

proc unwrapStream*(instance: Instance, stream: schemas.Stream): Future[tuple[fd: cint, holder: Holder]] {.async.} =
  ## Turns (possibly remote) Stream into file descriptor.
  let boundSocket = await bindSocketForConnect(parseAddress(instance.address), 0)
  let localAddr = boundSocket.getSockAddr()

  let info = await stream.tcpListen(
    remote=instance.nodeAddress,
    port=localAddr.port.int32
  )
  echo info.pprint
  if info.local.ip == nil: raise newException(ValueError, "bad address")

  let fd = await connectTcpAsFd(TcpConnectionData(
    host: parseAddress(info.local.ip),
    port: info.port,
    boundSocket: boundSocket))

  return (fd, info.holder)

proc wrapStream*(instance: Instance, stream: BytePipe): schemas.Stream =
  proc acceptConnections(remote: schemas.NodeAddress, port: int32, server: TcpServer): Future[void] {.async.} =
    asyncFor conn in server.incomingConnections:
      let address = conn.getPeerAddr
      if address.address != parseAddress(remote.ip) or address.port != port:
        stderr.writeLine "stream: invalid host attempted connection (host: [$1]:$2, expected: [$3]:$4)" % [
          $address.address, $address.port, $parseAddress(remote.ip), $port]

      server.incomingConnections.recvClose(JustClose)
      pipe(conn.BytePipe, stream)
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
  
  let cap = schemas.Stream.inlineCap(StreamInlineImpl(tcpListen: tcpListenImpl))
  return cap
