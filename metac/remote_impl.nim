import xrest, metac/remote, strutils, metac/service_common, metac/rest_common, metac/os_fs, reactor/unix, collections, backplane, metac/flatdb, json, sodium/sha2

{.reorder: on.}

type
  RemoteServiceImpl* = ref object
    db: FlatDb
    bp: Backplane

# --- CLIENT ----

proc localRequest(r: RemoteServiceImpl, req: HttpRequest): Future[HttpResponse] {.async.} =
  # TODO: reuse control channel
  let id = req.splitPath[0]
  let binaryId = urlsafeBase64Decode(id)
  assert binaryId.len == 48
  let peerId = PeerAddr(binaryId[0..<32])
  let bpConn = await connect(r.bp, peerId, "metac-remote-control")
  let controlChannel = newSctpConn(Pipe[Buffer](input: bpConn.input, output: bpConn.output))

  let isSctpRequest = (req.headers.getOrDefault("upgrade") == "sctp")

  await controlChannel.sctpPackets.output.send(SctpPacket(data: makeHeaders(req)))

  let responseHeadersBody = await controlChannel.sctpPackets.input.receive()
  let headersStream = newConstInput(responseHeadersBody.data)
  var response = await readResponseHeaders(headersStream)

  if response.statusCode == 101:
    echo response
    doAssert isSctpRequest
    doAssert response.headers["upgrade"] == "sctp"

    let id = response.headers["x-remote-id"]
    let bpDataConn = await connect(r.bp, peerId, "metac-remote-data-" & id)

    let (dataInput, output) = newInputOutputPair[byte]()
    response.dataInput = dataInput

    pipe(readBuffersPrefixed(req.data.get), bpDataConn.output).onFinishClose(bpDataConn.output)
    pipe(bpDataConn.input, writeBuffersPrefixed(output)).onFinishClose(output)
  else:
    # remove hop by hop headers
    response.headers.del("connection")
    response.headers.del("transfer-encoding")
    response.headers.del("upgrade")

    response.dataInput = headersStream

  return response

# --- SERVER ----

proc hashId(id: string): string =
  # hash the identifier, to avoid exposing sensitive information as filename
  return sha512d(id).toBinaryString[0..<16].encodeHex

proc sanitizeJson(node: JsonNode): JsonNode =
  proc transform(r: string): string =
    if r.startswith("/remote/"):
      return r
    else:
      raise newException(Exception, "illegal remote reference ($1)" % [r])

  return transformRef(node, transform)

proc safeJoinUrl(a: string, b: seq[string]): string =
  result = a
  if result[^1] != '/':
    result &= "/"
  for seg in b:
    if seg == "" or seg == "." or seg == "..":
      raise newException(Exception, "invalid URL")

    result &= seg
    result &= "/"

proc handleRemoteSctpRequest(r: RemoteServiceImpl, serviceConn: HttpConnection, req: HttpRequest): Future[HttpResponse] {.async.} =
  await serviceConn.sendOnlyRequest(req)
  let response = await serviceConn.readHeaders
  doAssert response.headers["upgrade"] == "sctp"

  if response.statusCode != 101:
    await serviceConn.readResponseBody(response)
    return response

  let rawConn = serviceConn.conn

  let topicId = hexUrandom()
  let socket = await r.bp.listen("metac-remote-data-" & topicId)
  socket.receive.then(proc(bp: BackplaneConn) =
      pipe(readBuffersPrefixed(rawConn.input), bp.output).onFinishClose(bp.output)
      pipe(bp.input, writeBuffersPrefixed(rawConn.output)).onFinishClose(rawConn.output)
  ).ignore # TODO: timeout

  response.headers["x-remote-id"] = topicId
  response.dataInput = newConstInput("")
  return response

proc handleRemoteNormalRequest(r: RemoteServiceImpl, serviceConn: HttpConnection, req: HttpRequest): Future[HttpResponse] {.async.} =
  const sizeLimit = 1024 * 1024
  var req = req
  var dataInput = none(ByteInput)
  if req.data.isSome:
    let data = await req.data.get.readUntilEof(sizeLimit)
    if data.len >= sizeLimit: raise newException(Exception, "request body too large")

    if req.headers.getOrDefault("content-type") == "application/json":
      let transformed = $sanitizeJson(parseJson(data))
      req.data = some(newConstInput(transformed))
    else:
      raise newException(Exception, "[remote] unsupported request content type")

  return serviceConn.request(req)

proc handleRemoteRequest(r: RemoteServiceImpl, req: HttpRequest): Future[HttpResponse] {.async.} =
  let id = req.splitPath[0]
  if hashId(id) notin r.db:
    return newHttpResponse("no such remote ref", statusCode=404)

  let refInfo = r.db[hashId(id)].fromJson(Exported)
  assert refInfo.secretId == id
  let fullUrl = safeJoinUrl(refInfo.localUrl, req.splitPath[1..^1])
  assert fullUrl.len > 0 and fullUrl[0] == '/'
  echo "remote request ", fullUrl
  let (service, servicePath) = fullUrl[1..^1].split2("/")

  let serviceConn = await serviceConnect(service)
  let newReq = HttpRequest(
    httpMethod: req.httpMethod,
    path: "/" & servicePath,
    headers: req.headers,
    data: req.data,
  )
  
  if req.headers.getOrDefault("upgrade") == "sctp":
    return handleRemoteSctpRequest(r, serviceConn, newReq)
  else:
    return handleRemoteNormalRequest(r, serviceConn, newReq)

proc serializeResponse(r: HttpResponse): Future[string] {.async.} =
  let (i,o) = newInputOutputPair[byte](128 * 1024) # if we exceed buffer size, bad things happen
  await writeResponse(o, r, close=true) # need `close=true` to avoid chunked transfer encoding
  o.sendClose
  return i.readUntilEof()

proc handleRemoteConn(r: RemoteServiceImpl, conn: BackplaneConn) {.async.} =
  let sctpConn = newSctpConn(Pipe[Buffer](input: conn.input, output: conn.output))

  asyncFor packet in sctpConn.sctpPackets.input:
    if packet.streamId != 0: continue

    let req = await readRequest(newConstInput(packet.data))
    let response = await handleRemoteRequest(r, req)
    let responseStr = await serializeResponse(response)
    await sctpConn.sctpPackets.output.send(SctpPacket(data: responseStr))

proc generateId(r: RemoteServiceImpl): string =
  var s = ""
  s &= string(r.bp.localAddr)
  s &= urandom(16)
  return urlsafeBase64Encode(s)

proc `create`(r: RemoteServiceImpl, info: Exported): Future[ExportedRef] {.async.} =
  var info = info
  info.secretId = r.generateId
  let id = hashId(info.secretId)

  r.db[id] = toJson(info)
  assert info.localUrl != ""

  return makeRef(ExportedRef, id)

proc `get`(r: RemoteServiceImpl): Future[seq[ExportedRef]] {.async.} =
  return toSeq(r.db.keys).mapIt(makeRef(ExportedRef, it))

proc `item/get`(r: RemoteServiceImpl, id: string): Future[Exported] {.async.} =
  return r.db[id].fromJson(Exported)

proc `item/delete`(r: RemoteServiceImpl, id: string) =
  r.db.delete(id)

proc main*() {.async.} =
  let bp = await defaultBackplane()
  let s = RemoteServiceImpl(
    db: makeFlatDB(getConfigDir() / "metac" / "remote"),
    bp: bp,
  )

  let conns = await bp.listen("metac-remote-control")
  conns.forEach(proc(conn: BackplaneConn) = handleRemoteConn(s, conn).ignore).onErrorQuit

  runService("exported", restHandler(ExportedCollection, s)).onErrorQuit
  await runService("remote", (r) => localRequest(s, r))

when isMainModule:
  main().runMain
