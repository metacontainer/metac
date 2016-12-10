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
