import metac/schemas, metac/instance, reactor, collections, typetraits, collections/bytes

type
  PersistenceDelegate* = (proc(cap: CapServer, rgroup: ResourceGroup, persistent: bool): Future[MetacSturdyRef])

  PersistableObj* = ref object of RootRef
    persistenceDelegate*: PersistenceDelegate

proc createSturdyRef*[T: PersistableObj](self: T, rgroup: ResourceGroup, persistent: bool): Future[MetacSturdyRef] =
  if self.persistenceDelegate == nil:
    return error(MetacSturdyRef, "persistence not supported (for: " & self.pprint & ")")

  return self.persistenceDelegate(self.toCapServer, rgroup, persistent)

proc wait*[T: PersistableObj](self: T): Future[void] =
  ## Default wait the never returns. (The method will appear to return on receiver side when the connection is broken)
  return waitForever()

proc summary*[T: PersistableObj](self: T): Future[string] {.async.} =
  ## Return object summary
  return self.pprint

proc makePersistenceDelegate*(instance: ServiceInstance, category: string, description: AnyPointer, runtimeId: string=nil): PersistenceDelegate =
  let runtimeId = if runtimeId == nil: hexUrandom(32) else: runtimeId

  return proc(cap: CapServer, rgroup: ResourceGroup, persistent: bool): Future[MetacSturdyRef] =
           let capDescription = CapDescription(runtimeId: runtimeId, category: category, description: description)
           return instance.persistenceHandler.createSturdyRef(rgroup, capDescription, persistent, cap.toAnyPointer)

proc makePersistenceCallDelegate*[T, A](instance: ServiceInstance, cap: T, args: A, runtimeId: string=nil): PersistenceDelegate =
  # FIXME: runtimeId doesn't work here
  mixin getInterfaceId, getMethodId
  return makePersistenceDelegate(instance, "persistence:call",
                                 schemas.Call(cap: cap.toAnyPointer, interfaceId: getInterfaceId(T), methodId: getMethodId(A), args: args.toAnyPointer).toAnyPointer,
                                 runtimeId=runtimeId)

proc injectPersistence*[T](cap: T, delegate: PersistenceDelegate): T =
  proc myCreateSturdyRef(rgroup: ResourceGroup, persistent: bool): Future[MetacSturdyRef] =
    return delegate(cap.toCapServer, rgroup, persistent)

  return injectInterface(cap, Persistable, inlineCap(Persistable, PersistableInlineImpl(createSturdyRef: myCreateSturdyRef)).toCapServer)

proc injectPersistence*[T](instance: ServiceInstance, cap: T, category: string, description: AnyPointer, runtimeId: string=nil): T =
  return injectPersistence(instance, cap, makePersistenceDelegate(category, description, runtimeId))

# proc callWithPersistence*[T, A](instance: ServiceInstance, cap: T, args: A, runtimeId: string = nil): auto =
#   let delegate = makePersistenceCallDelegate(instance, cap, args, runtimeId)
#   let retVal = cap.toCapServer.call(getInterfaceId(T), getMethodId(args), args.toAnyPointer)
#   return injectPersistence(retVal, delegate)

proc injectBasicPersistence*[T](instance: ServiceInstance, cap: T): T =
  ## Adds basic persistence support to cap ``cap``. (Basic meaning that it only works when ``persistent`` is set to false)
  return injectPersistence(instance, cap, nil, nil, nil)

proc registerRestorer*(instance: ServiceInstance, restorer: proc(description: CapDescription): Future[AnyPointer]): Future[void] =
  return instance.persistenceHandler.registerRestorer(inlineCap(Restorer, RestorerInlineImpl(
    restoreFromDescription: restorer
  )))

proc restore*(instance: Instance, m: MetacSturdyRef): Future[AnyPointer] =
  return instance.connect(m.node).getService(m.service).restore(m.objectInfo)

proc formatSturdyRef*(m: MetacSturdyRef): string =
  if not validIdentifier(m.service.named):
    raise newException(Exception, "invalid service name")

  discard parseAddress(m.node.ip)

  let name = if m.service.named == "persistence": ""
             else: m.service.named & "/"

  return "ref://[" & m.node.ip & "]/" & name & urlsafeBase64Encode(packPointer(m.objectInfo).compressCapnp)

proc parseSturdyRef*(s: string): MetacSturdyRef =
  if not s.startswith("ref://"):
    raise newException(ValueError, "invalid sturdy ref ($1), doesn't begin with ref://" % s)

  let spl = s.split('/')
  if spl.len notin {4, 5}:
    raise newException(ValueError, "invalid sturdy ref ($1), too many slashes")
  let ip = spl[2].strip(trailing=false, chars={'['}).strip(leading=false, chars={']'})
  let serviceName = if spl.len == 4: "persistence"
                    else: spl[3]
  let data = spl[^1]
  if not validIdentifier(serviceName):
    raise newException(ValueError, "invalid service name")
  let objectInfo = newUnpackerFlat(urlsafeBase64Decode(data).decompressCapnp).unpackPointer(0, AnyPointer)

  return MetacSturdyRef(node: NodeAddress(ip: ip),
                        service: ServiceId(kind: ServiceIdKind.named, named: serviceName),
                        objectInfo: objectInfo)

proc makePersistentPayload(data: AnyPointer, rgroup: ResourceGroup): Future[PersistentPayload] {.async.} =
  var caps: seq[CapServer] = @[]

  proc capToIndex(cap: CapServer): int =
    if cap.isNullCap:
      return -1
    caps.add(cap)
    return caps.len - 1

  let newData = data.packNow(capToIndex)
  var capTable: seq[MetacSturdyRef] = @[]
  for cap in caps:
    let sref = await cap.castAs(Persistable).createSturdyRef(rgroup, true)
    capTable.add(sref)

  return PersistentPayload(content: newData, capTable: capTable)

proc unpackPersistentPayload(instance: Instance, payload: PersistentPayload): Future[AnyPointer] {.async.} =
  var caps: seq[CapServer] = @[]
  for item in payload.capTable:
    let cap = await instance.restore(item).castAs(CapServer)
    caps.add cap

  payload.content.setCapGetter(proc(id: int): CapServer =
                                   if id == -1: return nullCap
                                   if id < 0 or id >= caps.len:
                                     raise newException(system.Exception, "invalid capability")
                                   return caps[id])
  return payload.content


proc packWithCaps*[T](data: T, rgroup: ResourceGroup): Future[string] {.async.} =
  let payload = await makePersistentPayload(data.toAnyPointer, rgroup)
  return packPointer(payload)

proc unpackWithCaps*[T](instance: Instance, data: string, typ: typedesc[T]): Future[T] {.async.} =
  let payload = newUnpackerFlat(data).unpackPointer(0, PersistentPayload)
  return unpackPersistentPayload(instance, payload).castAs(T)
