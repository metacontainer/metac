import metac/schemas, metac/instance, reactor, collections, typetraits, collections/bytes

proc injectPersistence*[T](instance: ServiceInstance, cap: T, category: string, description: AnyPointer, runtimeId: string=nil): T =
  let runtimeId = if runtimeId == nil: hexUrandom(32) else: runtimeId

  proc myCreateSturdyRef(rgroup: ResourceGroup, persistent: bool): Future[MetacSturdyRef] =
    let capDescription = CapDescription(runtimeId: runtimeId, category: category, description: description)
    return instance.persistenceHandler.createSturdyRef(rgroup, capDescription, persistent, cap.toAnyPointer)

  return injectInterface(cap, Persistable, inlineCap(Persistable, PersistableInlineImpl(createSturdyRef: myCreateSturdyRef)).toCapServer)

proc registerRestorer*(instance: ServiceInstance, restorer: proc(description: CapDescription): Future[AnyPointer]): Future[void] =
  return instance.persistenceHandler.registerRestorer(inlineCap(Restorer, RestorerInlineImpl(
    restoreFromDescription: restorer
  )))

proc restore*(instance: Instance, m: MetacSturdyRef): Future[AnyPointer] =
  return instance.connect(m.node).getService(m.service).restore(m.objectInfo)

proc formatSturdyRef*(m: MetacSturdyRef): string =
  if "/" in m.service.named:
    raise newException(Exception, "invalid service name")

  discard parseAddress(m.node.ip)

  return "ref://[" & m.node.ip & "]/" & m.service.named & "/" & urlsafeBase64Encode(packPointer(m.objectInfo).compressCapnp)

proc parseSturdyRef*(s: string): MetacSturdyRef =
  if not s.startswith("ref://"):
    raise newException(ValueError, "invalid sturdy ref ($1), doesn't begin with ref://" % s)

  let spl = s.split('/')
  let ip = spl[2].strip(trailing=false, chars={'['}).strip(leading=false, chars={']'})
  let serviceName = spl[3]
  let objectInfo = newUnpackerFlat(urlsafeBase64Decode(spl[4]).decompressCapnp).unpackPointer(0, AnyPointer)

  return MetacSturdyRef(node: NodeAddress(ip: ip),
                        service: ServiceId(kind: ServiceIdKind.named, named: serviceName),
                        objectInfo: objectInfo)
