import metac/schemas, caprpc, posix, reactor, reactor/unix, os, tables, collections

type
  Instance* = ref object
    rpcSystem: RpcSystem
    localRequests*: TableRef[string, RootRef] # for castToLocal
    address*: string
    thisNode*: Node
    thisNodeAdmin*: NodeAdmin
    isAdmin*: bool

  ServiceInstance* = ref object
    instance*: Instance
    persistenceHandler*: ServicePersistenceHandler
    serviceName: string

let notAuthorized* = inlineCap(CapServer, CapServerInlineImpl(
  call: (proc(ifaceId: uint64, methodId: uint64, args: AnyPointer): Future[AnyPointer] =
             return now(error(AnyPointer, "not authorized to access admin interface (run as root)")))
))

proc newInstance*(address: string): Future[Instance] {.async.} =
  let self = Instance()
  self.isAdmin = getuid() == 0
  self.address = address
  self.localRequests = newTable[string, RootRef]()

  var conn: BytePipe
  if self.isAdmin:
    conn = await connectUnix("/run/metac/" & address & "/socket")
  else:
    conn = await connectTcp(address, 901)

  self.rpcSystem = newRpcSystem(newTwoPartyNetwork(conn, Side.client).asVatNetwork)

  if self.isAdmin:
    self.thisNodeAdmin = (await self.rpcSystem.bootstrap()).castAs(NodeAdmin)
    self.thisNode = await self.thisNodeAdmin.getUnprivilegedNode()
  else:
    self.thisNodeAdmin = NodeAdmin.createFromCap(notAuthorized)
    self.thisNode = (await self.rpcSystem.bootstrap()).castAs(Node)

  return self

proc newInstance*(): Future[Instance] =
  for entry in walkDir("/run/metac", relative=true):
    return newInstance(entry.path)

  raise newException(Exception, "no instance in /run/metac, please run metac-bridge")

proc nodeAddress*(instance: Instance): NodeAddress =
  return NodeAddress(ip: instance.address)

proc getServiceAdmin*[T](instance: Instance, name: string, typ: typedesc[T]): Future[T] {.async.} =
  let service = await instance.thisNodeAdmin.getServiceAdmin(name)
  return service.castAs(T)

proc connect*(instance: Instance, address: NodeAddress): Future[Node] {.async.} =
  # TODO: multiparty RpcSystem
  let conn = await connectTcp(address.ip, 901)
  let rpcSystem = newRpcSystem(newTwoPartyNetwork(conn, Side.client).asVatNetwork)
  return rpcSystem.bootstrap().castAs(Node)

### ServiceInstance

proc newServiceInstance*(name: string): Future[ServiceInstance] {.async.} =
  let instance = await newInstance()
  let persistenceHandler = if name != "persistence":
                             await instance.getServiceAdmin("persistence", PersistenceServiceAdmin).getHandlerFor(ServiceId(kind: ServiceIdKind.named, named: name))
                           else:
                             nullCap

  return ServiceInstance(instance: instance, serviceName: name, persistenceHandler: persistenceHandler)

proc runService*(sinstance: ServiceInstance, service: Service, adminBootstrap: ServiceAdmin) {.async.} =
  ## Helper method for registering and running a service
  let holder = await sinstance.instance.thisNodeAdmin.registerNamedService(sinstance.serviceName, service, adminBootstrap)
  await waitForever()

converter toInstance*(s: ServiceInstance): Instance =
  return s.instance

### castToLocal

template enableCastToLocal*(T) =
  proc registerLocal*(self: T, key: string) {.async.} =
    if key notin self.instance.toInstance.localRequests:
      asyncRaise "invalid key"

    self.instance.toInstance.localRequests[key] = self

proc toLocal*[T, R](instance: Instance, self: T, target: typedesc[R]): Future[R] {.async.} =
  let key = hexUrandom(16)
  instance.localRequests[key] = nil
  await self.castAs(CastToLocal).registerLocal(key)
  let val = instance.localRequests[key]
  instance.localRequests.del key
  if val == nil:
    asyncRaise "toLocal request not completed"
  if not (val of R):
    asyncRaise "toLocal response bad type"
  return val.R

###

type HolderImpl[T] = ref object of RootRef
  obj: T

proc toCapServer*(self: HolderImpl): CapServer =
  return toGenericCapServer(self.asHolder)

proc holder*[T](t: T): schemas.Holder =
  when T is void:
    return HolderImpl[T]().asHolder
  else:
    return HolderImpl[T](obj: t).asHolder

### UTILS

proc waitForFile*(path: string) {.async.} =
  var buf: Stat
  while stat(path.cstring, buf) != 0:
    await asyncSleep(10)

proc fakeUsage*(a: any) =
  # forces GC to keep `a` to the point of this call
  var v {.volatile.} = a
