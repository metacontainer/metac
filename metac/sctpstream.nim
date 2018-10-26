import macros, xrest, sctp

proc sctpStreamClient*(r: RestRef): SctpConn =
  discard

proc sctpStreamServer*(r: HttpRequest, conn: SctpConn): HttpResponse =
  discard

macro emitClient_sctpStream*(selfType: typed, resultType: typed, name: typed): untyped =
  let nameIdent = newIdentNode(name.strVal)
  return quote do:
    proc `nameIdent`*(self: `selfType`): SctpConn =
      return sctpStreamClient(appendPathFragment(RestRef(self), `name`))

template dispatchRequest_sub*(r: HttpRequest, callPath: untyped, name: string): untyped =
  if r.splitPath.len > 0 and r.splitPath[0] == name:
    if r.headers.getOrDefault("upgrade") == "sctp":
      let s: SctpConn = pathCall(pathAppend(callPath, (name, )))
      asyncReturn sctpStreamServer(r, s)
    else:
      asyncReturn newHttpResponse(data="<h1>SCTP upgrade required", statusCode=400)
