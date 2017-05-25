import reactor, caprpc, capnp, metac/schemas, metac/instance, metac/persistence, metac/process_util, os, posix, random, collections, osproc, morelinux/netlink

type
  KernelNetworkNamespaceImpl = ref object of PersistableObj
    # TODO: store namespace fd
    instance: ServiceInstance

  KernelInterfaceImpl = ref object of PersistableObj
    instance: ServiceInstance
    name: string
    isReal: bool

  L2InterfaceImpl = ref object of RootObj
    instance: ServiceInstance
    iface: KernelInterfaceImpl

  BindToImpl = ref object of RootObj

capServerImpl(BindToImpl, [Holder])

proc reserveVxlanPort(): tuple[sock: SocketHandle, port: int] =
  let sock = socket(AF_INET6, SOCK_DGRAM, 0).SocketHandle
  var address = SockAddr_in6(sin6_family: AF_INET6, sin6_port: 0, sin6_flowinfo: 0, sin6_scope_id: 0, sin6_addr: in6addr_any)
  var addrLen: Socklen = sizeof(address).Socklen
  if bindSocket(sock, cast[ptr SockAddr](addr address), addrLen) != 0:
    raise newException(Exception, "failed to bind port for VXLAN")

  if getsockname(sock, cast[ptr SockAddr](addr address), addr addrLen) != 0 or address.sin6_family != AF_INET6:
    raise newException(Exception, "getsockname failed")

  return (sock, address.sin6_port.int)

proc createBridge(name: string) {.async.} =
  await execCmd(@["ip", "link", "add", "name", name, "type", "bridge"])

proc setupBridgeFor(self: KernelInterfaceImpl): Future[string] {.async.} =
  var bridgeName: string
  let linkInfo: Option[NlLink] = getLink(self.name)

  if self.isReal:
    if linkInfo.isNone:
      asyncRaise "link doesn't exist"

    let masterFile = "/sys/class/net/" & self.name & "/master"
    if symlinkExists(masterFile):
      # this is a bridge port
      bridgeName = expandSymlink(masterFile).split("/")[1]
    elif linkInfo.get.kind == "bridge":
      # this is already a bridge
      bridgeName = self.name
    else:
      bridgeName = "mcbr" & hexUrandom(5)
      await createBridge(bridgeName)
      await execCmd(@["ip", "link", "set", "dev", self.name, "master", bridgeName])
  else:
    bridgeName = self.name
    if linkInfo.isNone:
      await createBridge(self.name)
    elif linkInfo.get.kind != "bridge":
      asyncRaise "'new' link already exists and is not a bridge!"

  await execCmd(@["ip", "link", "set", "dev", self.name, "up"])
  await execCmd(@["ip", "link", "set", "dev", bridgeName, "up"])
  return bridgeName

proc createVxlan(self: KernelInterfaceImpl, localPort: int, remote: NodeAddress, remotePort: int, vniNum: int): Future[void] {.async.} =
  let bridgeName = await setupBridgeFor(self)
  let vxlanName = "mcvx" & hexUrandom(5)
  var remote = parseAddress(remote.ip)

  await execCmd(@["ip", "link", "add", "name", vxlanName, "type", "vxlan", "id", $vniNum, "remote", $remote, "dstport", $remotePort, "srcport", $localPort, $(localPort+1)])
  await execCmd(@["ip", "link", "set", "dev", vxlanName, "master", bridgeName])
  await execCmd(@["ip", "link", "set", "dev", vxlanName, "up"])

  await execCmd(@["ipset", "add", "metacvxlan", $localPort])
  #await execCmd(@["ipset", "add", "metacvxlanips", "$1,udp:$2" % [$parseAddress(remote.ip), $remotePort]])

proc bindTo(selfL2: L2InterfaceImpl, other: L2Interface): Future[Holder] {.async.} =
  let self = selfL2.iface

  let (sock, port) = reserveVxlanPort()
  let vniNum = random(1 shl 24)
  # TODO: defer: close(sock)
  let otherSide = await other.setupVxlan(self.instance.nodeAddress, port.uint16, vniNum.uint32)

  if parseAddress(otherSide.local.ip) == parseAddress(self.instance.nodeAddress.ip):
    # use veth
    let otherLocalL2 = await self.instance.toLocal(other, L2InterfaceImpl)
    let otherLocal = otherLocalL2.iface
    let bridge1 = await setupBridgeFor(self)
    let bridge2 = await setupBridgeFor(otherLocal)
    let vethName = "mcve" & hexUrandom(5)
    await execCmd(@["ip", "link", "add", "name", vethName & "l", "type", "veth", "peer", "name", vethName & "r"])
    await execCmd(@["ip", "link", "set", "dev", vethName & "l", "master", bridge1, "up"])
    await execCmd(@["ip", "link", "set", "dev", vethName & "r", "master", bridge2, "up"])
  else:
    # use VXLAN
    await self.createVxlan(port.int, otherSide.local, otherSide.srcPort.int, vniNum)

  # TODO: interface leak, fd leak
  return BindToImpl().asHolder

proc setupVxlan(selfL2: L2InterfaceImpl, remote: NodeAddress, dstPort: uint16, vniNum: uint32): Future[L2Interface_setupVxlan_Result] {.async.} =
  let self = selfL2.iface

  if parseAddress(remote.ip) == parseAddress(self.instance.nodeAddress.ip):
    return L2Interface_setupVxlan_Result(local: self.instance.nodeAddress, srcPort: 0, holder: nullCap)

  let (sock, port) = reserveVxlanPort()

  await self.createVxlan(port.int, remote, dstPort.int, vniNum.int)
  return L2Interface_setupVxlan_Result(local: self.instance.nodeAddress, srcPort: port.uint16, holder: nullCap)

enableCastToLocal(L2InterfaceImpl)
capServerImpl(L2InterfaceImpl, [L2Interface, CastToLocal])

proc l2Interface(self: KernelInterfaceImpl): Future[L2Interface] {.async.}

proc getName(self: KernelInterfaceImpl): Future[string] {.async.} =
  return self.name

proc destroy(self: KernelInterfaceImpl): Future[void] {.async.} =
  return

proc rename(self: KernelInterfaceImpl, newname: string): Future[void] {.async.} =
  return

proc isHardware(self: KernelInterfaceImpl): Future[bool] {.async.} =
  return self.isReal # TODO: e.g. tunX are not hardware

capServerImpl(KernelInterfaceImpl, [KernelInterface])

proc l2Interface(self: KernelInterfaceImpl): Future[L2Interface] {.async.} =
  let iface = L2InterfaceImpl(iface: self, instance: self.instance).asL2Interface
  return injectPersistence(iface,
                           makePersistenceCallDelegate(self.instance, self.asKernelInterface,
                                                       KernelInterface_l2interface_Params()))

proc getInterface(self: KernelNetworkNamespaceImpl, name: string): Future[KernelInterface] {.async.} =
  let p = self.instance.makePersistenceDelegate("net:localnet", description=name.toAnyPointer, runtimeId=nil)

  return KernelInterfaceImpl(instance: self.instance, isReal: true, name: name, persistenceDelegate: p).asKernelInterface

proc listInterfaces(self: KernelNetworkNamespaceImpl): Future[seq[KernelInterface]] {.async.} =
  var s: seq[KernelInterface] = @[]
  # Nim bug!
  # for entry in walkDir("/sys/class/net", relative=true):
  #   let iface = await self.getInterface(entry.path)
  #   s.add(iface)
  return s

proc createInterface(self: KernelNetworkNamespaceImpl, name: string): Future[KernelInterface] {.async.} =
  let p = self.instance.makePersistenceDelegate("net:newlocalnet", description=name.toAnyPointer, runtimeId=nil)

  return KernelInterfaceImpl(instance: self.instance, isReal: false, name: name,
                             persistenceDelegate: p).asKernelInterface

capServerImpl(KernelNetworkNamespaceImpl, [KernelNetworkNamespace])

# Initialization

proc addRule(rule: string) =
  if execShellCmd("iptables -C" & rule & " 2>/dev/null") != 0:
    let ok = execShellCmd("iptables -A" & rule)
    if ok != 0:
      raise newException(Exception, "can't add iptables rule: " & rule)

proc init() =
  # (hash would be probably a better option)
  discard execShellCmd("ipset create metacvxlan bitmap:port range 1024-65535")
  discard execShellCmd("ipset create metacvxlanips hash:ip,port")

  addRule("FORWARD -m set --match-set metacvxlan src -j DROP")
  # --socket-exists doesn't match VXLAN data from kernel
  addRule("OUTPUT -m owner --socket-exists -m set --match-set metacvxlan src -j DROP")
  #addRule("INPUT -m set --match-set metacvxlan dst -m set ! --match-set metacvxlanips src -j DROP")

  # TODO(security): reject packets that are not coming from IP-port-port combinations
  # This isn't strictly neccessary, because dstport+vni is a ~39-bit secret.

proc main*() {.async.} =
  init()

  let instance = await newServiceInstance("network")

  let rootNamespace = KernelNetworkNamespaceImpl(instance: instance)

  let serviceAdmin = inlineCap(NetworkServiceAdmin, NetworkServiceAdminInlineImpl(
    rootNamespace: (() => now(just(rootNamespace.asKernelNetworkNamespace)))
  ))

  await instance.registerRestorer(
    proc(d: CapDescription): Future[AnyPointer] =
     case d.category:
      of "net:localnet":
        return error(AnyPointer, "unknown category")
      of "net:newlocalnet":
        return error(AnyPointer, "unknown category")
      else:
        return error(AnyPointer, "unknown category"))

  await instance.runService(
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=ServiceAdmin.createFromCap(serviceAdmin.toCapServer)
  )
