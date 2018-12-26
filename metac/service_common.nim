import reactor, reactor/unix, xrest, os, strutils, sequtils, reactor/http, metac/os_fs, metac/sctpstream, sctp

export os, sequtils

proc getRuntimePath*(): string =
  return getConfigDir() & "/metac/run/"

proc isServiceNameValid(name: string): bool =
  for ch in name:
    if ch notin Letters + Digits + {'_', '-'}:
      return false
  return true

proc getServiceSocketPath*(name: string): string =
  if not isServiceNameValid(name):
    raise newException(Exception, "invalid service name")

  return getRuntimePath() & "/service-" & name & ".socket"

proc serviceConnect*(name: string): Future[HttpConnection] {.async.} =
  let s = await connectUnix(getServiceSocketPath(name))
  return newHttpConnection(s, defaultHost=name)

proc getServiceRestRef*(name: string): Future[RestRef] {.async.} =
  proc transformRequest(req: HttpRequest) =
    let s = req.path[1..^1].split("/", 1)
    if s.len != 2 or s[0] != name:
      raise newException(Exception, "misdirected request (url=$1, service=$2)" % [req.path, name])

    req.path = "/" & s[1]

  let sess = createHttpSession(
    connectionFactory=(() => serviceConnect(name)),
    transformRequest=transformRequest)
  return RestRef(sess: sess, path: "/" & name & "/")

proc getRefForPath*(path: string): Future[RestRef] {.async.} =
  assert path[0] == '/'
  let s = path[1..^1].split('/', 1)
  let r = await getServiceRestRef(s[0])
  return RestRef(sess: r.sess, path: r.path & s[1])

proc getRefForPath*[T: distinct](path: string, t: typedesc[T]): Future[T] {.async.} =
  let r = await getRefForPath(path)
  return T(r)

proc getServiceRestRef*[T: distinct](name: string, t: typedesc[T]): Future[T] {.async.} =
  let r = await getServiceRestRef(name)
  return T(r)

proc runService*(name: string, handler: RestHandler) {.async.} =
  let server = createUnixServer(getServiceSocketPath(name))
  await server.incomingConnections.forEach(
    proc(conn: UnixConnection) =
      runHttpServer(conn, handler).ignore
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