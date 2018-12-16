import reactor, reactor/unix, xrest, os, strutils, sequtils, reactor/http

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
    let s = req.path[1..<1].split("/", 1)
    if s.len != 2 or s[0] != name:
      raise newException(Exception, "misdirected request")

    req.path = s[1]

  let sess = createHttpSession(
    connectionFactory=(() => serviceConnect(name)),
    transformRequest=transformRequest)
  return RestRef(sess: sess, path: "/" & name & "/")

proc getServiceRestRef*[T: distinct](name: string, t: typedesc[T]): Future[T] {.async.} =
  return T(getServiceRestRef(name))

proc runService*(name: string, handler: RestHandler) {.async.} =
  let server = createUnixServer(getServiceSocketPath(name))
  await server.incomingConnections.forEach(
    proc(conn: UnixConnection) =
      runHttpServer(conn, handler).ignore
  )

const helpersPath {.strdefine.} = "../helpers"

proc getHelperBinary*(name: string): string =
  return getAppDir() / helpersPath / name
