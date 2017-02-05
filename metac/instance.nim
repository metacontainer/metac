import metac/schemas, caprpc, posix, reactor, reactor/unix

type
  Instance* = ref object
    rpcSystem: RpcSystem
    address*: string
    thisNode*: Node
    thisNodeAdmin*: NodeAdmin
    isAdmin*: bool

proc newInstance*(address: string): Future[Instance] {.async.} =
  let self = Instance()
  self.isAdmin = getuid() == 0
  self.address = address

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
    self.thisNodeAdmin = NodeAdmin.createFromCap(nothingImplemented)
    self.thisNode = (await self.rpcSystem.bootstrap()).castAs(Node)

  return self

proc nodeAddress*(instance: Instance): NodeAddress =
  return NodeAddress(ip: instance.address)

type HolderImpl[T] = ref object of RootRef
  obj: T

proc toCapServer*(self: HolderImpl): CapServer =
  return toGenericCapServer(self.asHolder)

proc holder*[T](t: T): schemas.Holder =
  when T is void:
    return HolderImpl[T]().asHolder
  else:
    return HolderImpl[T](obj: t).asHolder
