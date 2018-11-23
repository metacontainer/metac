import macros, xrest, sctp, collections, reactor, xrest/pathcall

proc sctpStreamClient*(r: RestRef): Future[SctpConn] {.async.} =
  let conn = await r.sess.makeConnection()
  await conn.sendOnlyRequest(r.sess.createRequest(
    "POST", r.path, headers=headerTable({
      "connection": "upgrade",
      "upgrade": "sctp"})))

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
                          headers: headerTable({"connection": "upgrade"}))

  return (resp, sctpConn)

macro emitClient_sctpStream*(selfType: typed, resultType: typed, name: typed): untyped =
  let nameIdent = newIdentNode(name.strVal)
  return quote do:
    proc `nameIdent`*(self: `selfType`): Future[SctpConn] =
      return sctpStreamClient(appendPathFragment(RestRef(self), `name`))

template dispatchRequest_sctpStream*(r: HttpRequest, callPath: untyped, name: string): untyped =
  if r.splitPath.len > 0 and r.splitPath[0] == name:
    if r.headers.getOrDefault("upgrade") == "sctp":
      let (resp, sctpConn) = sctpStreamServer(r)
      let fut = pathCall(pathAppend(callPath, (name, sctpConn)))
      fut.onErrorClose(resp.dataInput)
      asyncReturn resp
    else:
      asyncReturn newHttpResponse(data="<h1>SCTP upgrade required", statusCode=400)
