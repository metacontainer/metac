import reactor, reactor/unix, xrest, os, strutils

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

proc runService*(name: string, handler: RestHandler) {.async.} =
  let server = createUnixServer(getServiceSocketPath(name))
  await server.incomingConnections.forEach(
    proc(conn: UnixConnection) =
      runHttpServer(conn, handler).ignore
  )
