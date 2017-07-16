import capnp, reactor, metac/schemas, collections, os, reactor/unix, metac/process_util

type
  InternalServiceId = tuple[isNamed: bool, name: string]

  Bridge = ref object of RootObj
    services: TableRef[InternalServiceId, ServiceInfo]
    nodeAddress: string
    waitFor: TableRef[InternalServiceId, Completer[void]]

  ServiceInfo = tuple[service: Service, serviceAdmin: ServiceAdmin]

  ServiceHolder = ref object of RootRef
    bridge: Bridge
    id: InternalServiceId

forwardDecl(Node, bridge, Bridge)
forwardDecl(NodeAdmin, bridge, Bridge)

capServerImpl(Bridge, [Node, NodeAdmin])

proc wait(h: ServiceHolder) {.async.} =
  await waitForever()

capServerImpl(ServiceHolder, [Holder, Waitable])

proc unregisterService(holder: ServiceHolder) =
  holder.bridge.services.del holder.id

proc registerNamedService(bridge: Bridge, name: string, service: Service, adminBootstrap: ServiceAdmin): Future[Holder] {.async.} =
  let iid = (true, name)
  bridge.services[iid] = (service, adminBootstrap)

  if iid in bridge.waitFor:
    bridge.waitFor[iid].complete
    bridge.waitFor.del iid

  var holder: ServiceHolder
  new(holder, unregisterService)
  holder.bridge = bridge
  holder.id = (true, name)
  return holder.asHolder

proc getServiceAdmin(bridge: Bridge, name: string): Future[ServiceAdmin]  {.async.} =
  return bridge.services[(true, name)].serviceAdmin

proc toInternalId(id: schemas.ServiceId): InternalServiceId =
  if id.kind == schemas.ServiceIdKind.named:
    return (true, id.named)
  else:
    return (false, id.anonymous)

proc getService(bridge: Bridge, id: schemas.ServiceId): Future[Service] {.async.} =
  return bridge.services[toInternalId(id)].service

proc waitForService(bridge: Bridge, id: schemas.ServiceId): Future[void] {.async.} =
  let iid = toInternalId(id)
  if iid in bridge.services:
    return

  if iid notin bridge.waitFor:
    bridge.waitFor[iid] = newCompleter[void]()

  await bridge.waitFor[iid].getFuture

proc getUnprivilegedNode(bridge: Bridge): Future[Node] {.async.} =
  return restrictInterfaces(bridge, Node)

proc registerAnonymousService(bridge: Bridge, service: Service): Future[Node_registerAnonymousService_Result] {.async.} =
  asyncRaise "not implemented"

proc address(bridge: Bridge): Future[NodeAddress] {.async.} =
  return NodeAddress(ip: bridge.nodeAddress)

proc main*() {.async.} =
  enableGcNoDelay()

  let nodeAddr = if existsEnv("METAC_ADDRESS"):
                   getEnv("METAC_ADDRESS")
                 else:
                   paramStr(2)
  let baseDir = "/run/metac/" & nodeAddr
  createDir("/run/metac")
  createDir(baseDir)

  let bridge = Bridge(services: newTable[InternalServiceId, ServiceInfo](),
                      waitFor: newTable[InternalServiceId, Completer[void]](),
                      nodeAddress: nodeAddr)

  let node = restrictInterfaces(bridge, Node)
  let nodeAdmin = restrictInterfaces(bridge, NodeAdmin)

  let socketPath = baseDir & "/socket"
  removeFile(socketPath)

  let tcpServer = await createTcpServer(addresses = @[parseAddress(nodeAddr)], port=901)
  tcpServer.incomingConnections.forEach(proc(conn: auto) = discard newTwoPartyServer(conn, node.toCapServer)).ignore

  let unixServer = createUnixServer(socketPath)
  unixServer.incomingConnections.forEach(proc(conn: auto) = discard newTwoPartyServer(conn, nodeAdmin.toCapServer)).ignore

  await systemdNotifyReady()
  await waitForever()
