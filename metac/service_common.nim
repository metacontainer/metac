import reactor, reactor/unix, xrest, os, strutils, sequtils, reactor/http, metac/os_fs, metac/sctpstream, sctp, json, posix, collections

export os, sequtils

proc getMetacConfigDir*(): string =
  if getuid() == 0:
    return "/etc/metac"
  else:
    return getConfigDir() / "metac"

proc getRuntimePath*(): string =
  if getuid() == 0:
    return "/run/metac"
  else:
    return getMetacConfigDir() / "run"

proc isServiceNameValid(name: string): bool =
  if '\0' in name or name == "": return false
  for ch in name:
    if ch notin Letters + Digits + {'_', '-'}:
      return false
  return true

proc getServiceSocketPath*(name: string): string =
  if not isServiceNameValid(name):
    raise newException(Exception, "invalid service name ($1)" % name)

  return getRuntimePath() & "/service-" & name & ".socket"

proc serviceConnect*(name: string): Future[HttpConnection] {.async.} =
  let s = await connectUnix(getServiceSocketPath(name))
  return newHttpConnection(s, defaultHost=name)

proc getRootRestRef*(): RestRef =
  proc transformRequest(req: HttpRequest) =
    let s = req.path[1..^1].split("/", 1)
    req.path = "/" & s[1]

  proc connectionFactory(req: HttpRequest): Future[HttpConnection] {.async.} =
    let s = req.path[1..^1].split("/", 1)
    if s[0] == "":
      raise newException(ValueError, "cannot connect to root path ('/')")
    return serviceConnect(s[0])

  let sess = createHttpSession(
    connectionFactory=connectionFactory,
    transformRequest=transformRequest)
  return RestRef(sess: sess, path: "/")

proc getServiceRestRef*(name: string): Future[RestRef] {.async.} =
  let r = getRootRestRef()
  if not isServiceNameValid(name):
    raise newException(Exception, "invalid service name")

  return r / name

proc getRefForPath*(path: string): Future[RestRef] {.async.} =
  var r = getRootRestRef()
  for seg in path.split('/'):
    if seg != "":
      r = r / seg
  return r

proc getRefForPath*[T: distinct](path: string, t: typedesc[T]): Future[T] {.async.} =
  let r = await getRefForPath(path)
  return T(r)

proc getServiceRestRef*[T: distinct](name: string, t: typedesc[T]): Future[T] {.async.} =
  let r = await getServiceRestRef(name)
  return T(r)

proc serviceHandlerWrapper(handler: RestHandler, req: HttpRequest): Future[HttpResponse] {.async.} =
  if req.headers.getOrDefault("upgrade").toLowerAscii == "websocket":
    # WebSocket<->SCTP bridge for better compat with non-Nim clients
    return wrapSctpWebsocket(handler, req)
  else:
    return handler(req)

proc runService*(name: string, handler: RestHandler) {.async.} =
  createDir(getRuntimePath())
  let server = createUnixServer(getServiceSocketPath(name))
  await server.incomingConnections.forEach(
    proc(conn: UnixConnection) =
      runHttpServer(conn, proc(r: HttpRequest): auto = serviceHandlerWrapper(handler, r)).ignore
  )

const helpersPath {.strdefine.} = "../helpers"

proc getHelperBinary*(name: string): string =
  return getAppDir() / helpersPath / name

proc sctpStreamAsUnixSocket*(r: RestRef, queryString=""): Future[tuple[path: string, cleanup: proc()]] {.async.} =
  let (dir, sockCleanup) = createUnixSocketDir()
  let path = dir / "socket"
  let s = createUnixServer(path)

  proc handleClient(client: BytePipe) {.async.} =
    let conn = await sctpStreamClient(r, queryString)
    await pipe(conn, client)

  s.incomingConnections.forEach(
    proc(p: UnixConnection) = handleClient(p).ignore
  ).ignore()

  proc cleanup() =
    sockCleanup()
    s.close

  return (path, cleanup)

proc pipeStdio*(conn: SctpConn, process: Process) {.async.} =
  await zipVoid(@[
    pipe(conn, process.files[0].output, close=true),
    pipe(process.files[1].input, conn, close=true)
  ])

proc dbFromJson*[T](j: JsonNode, t: typedesc[T]): Future[T] {.async.} =
  let rootRef = getRootRestRef()
  let ctx = RestRefContext(r: rootRef)
  return fromJson(ctx, j, T)

proc expandResourcePath*(path: string): string =
  # contains some convenience aliases
  if path.startswith("file:"):
    return "/fs/file/" & urlEncode(absolutePath(path[5..^1])) & "/"
  elif path.startswith("fs:"):
    return "/fs/fs/" & urlEncode(absolutePath(path[3..^1])) & "/"
  elif not path.startswith("/"):
    raise newException(Exception, "resource path ($1) doesn't start with '/'" % path)
  else:
    return path
