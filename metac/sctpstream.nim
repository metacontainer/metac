import macros, xrest, sctp, collections, reactor, xrest/pathcall, reactor/http/websocket

proc sctpStreamClient*(r: RestRef, queryString=""): Future[SctpConn] {.async.} =
  var path = r.path
  if queryString != "":
    path &= "?" & queryString

  let req = newHttpRequest(
    "POST", path, headers=headerTable({
      "connection": "upgrade",
      "upgrade": "sctp"}))
  let conn = await r.sess.makeConnection(req)

  await conn.sendOnlyRequest(r.sess.createRequest(req))

  let resp = await conn.readHeaders()

  if resp.statusCode != 101:
    raise newException(Exception, "SCTP Upgrade request returned unexpected $1" % $resp.statusCode)

  return newSctpConn(Pipe[Buffer](
    input: readBuffersPrefixed(conn.conn.input),
    output: writeBuffersPrefixed(conn.conn.output),
  ))

proc sctpStreamServer*(r: HttpRequest): (HttpResponse, SctpConn) =
  let (input, output) = newInputOutputPair[byte]()

  let sctpConn = newSctpConn(Pipe[Buffer](
    input: readBuffersPrefixed(r.data.get),
    output: writeBuffersPrefixed(output),
  ))
  let resp = HttpResponse(statusCode: 101, dataInput: input,
                          headers: headerTable({"connection": "upgrade", "upgrade": "sctp"}))

  return (resp, sctpConn)

macro emitClient_sctpStream*(selfType: typed, resultType: typed, name: typed): untyped =
  let nameIdent = newIdentNode(name.strVal)
  return quote do:
    proc `nameIdent`*(self: `selfType`, queryString=""): Future[SctpConn] =
      return sctpStreamClient(appendPathFragment(RestRef(self), `name`), queryString)

template dispatchRequest_sctpStream*(r: HttpRequest, callPath: untyped, name: string): untyped =
  if r.splitPath.len > 0 and r.splitPath[0] == name:
    if r.headers.getOrDefault("upgrade") == "sctp":
      let (resp, sctpConn) = sctpStreamServer(r)

      let fut = pathCall(pathAppend(callPath, (name, sctpConn, r)))
      fut.ignore
      fut.onErrorClose(resp.dataInput)
      asyncReturn resp
    else:
      stderr.writeLine("invalid upgrade ($1)" % r.headers.getOrDefault("upgrade"))
      asyncReturn newHttpResponse(data="<h1>SCTP upgrade required", statusCode=400)

proc wrapSctpWebsocket*(handler: RestHandler, req: HttpRequest): Future[HttpResponse] {.async.} =
   let newReq = newHttpRequest(
     "POST", req.path, headers=headerTable({
       "connection": "upgrade",
       "upgrade": "sctp"}))
   let (input, output) = newInputOutputPair[byte]()
   newReq.data = some(input)
   let resp = await handler(newReq)

   if resp.statusCode != 101:
    return resp

   let sctpConn = newSctpConn(Pipe[Buffer](
     input: readBuffersPrefixed(resp.dataInput),
     output: writeBuffersPrefixed(output),
   ))

   proc pipeIn(conn: WebsocketConnection) {.async.} =
     defer:
       conn.close
       sctpConn.close

     while true:
       let msg = await conn.readMessage
       await sctpConn.sctpPackets.output.send(SctpPacket(data: msg.data))

   proc pipeOut(conn: WebsocketConnection) {.async.} =
     defer:
       conn.close
       sctpConn.close

     asyncFor packet in sctpConn.sctpPackets.input:
       await conn.writeMessage(WebsocketMessage(
         kind: WebsocketMessageKind.binary, data: packet.data))

   let wsResp = await websocketServerCallback(
     proc(r: HttpRequest, conn: WebsocketConnection): Future[void] =
       return zipVoid(@[
         pipeIn(conn),
         pipeOut(conn)
       ])
   )(req)
   wsResp.headers["Sec-WebSocket-Protocol"] = "binary"
   return wsResp
