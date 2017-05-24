import tables, reactor, capnp, caprpc, strutils, metac/schemas, metac/instance, collections, db_sqlite, metac/persistence

type
  PersistenceServiceImpl = ref object of RootObj
    instance: Instance
    handlers: TableRef[string, ServicePersistenceHandlerImpl]
    dbConn: DbConn

  StoredCap = ref object
    runtimeId: string
    category: string
    description: Future[AnyPointer]
    persistent: bool

    cap: Future[CapServer]
    capCompleter: Completer[CapServer]
    isRestoreStarted: bool

  ServicePersistenceHandlerImpl = ref object of RootObj
    service: PersistenceServiceImpl
    instance: Instance
    name: string

    capByRuntimeId: TableRef[string, StoredCap]
    capBySturdyRef: TableRef[string, StoredCap]

proc restoreInternal(storedCap: StoredCap): Future[CapServer] {.async.} =
  if storedCap.category == "persistence:call":
    let callDescr = storedCap.description.get.castAs(Call)
    let retStruct = await callDescr.cap.castAs(CapServer).call(callDescr.interfaceId, callDescr.methodId, callDescr.args)
    return retStruct.getPointerField(0).castAs(CapServer)
  else:
    raise newException(ValueError, "bad category")

proc restoreUsingRestorer(storedCap: StoredCap, restorer: Restorer): Future[CapServer] {.async.} =
  let description = await storedCap.description
  if storedCap.category.startsWith("persistence:"):
    return restoreInternal(storedCap)
  else:
    return restorer.restoreFromDescription(CapDescription(category: storedCap.category, runtimeId: storedCap.runtimeId, description: description)).castAs(CapServer)

proc registerRestorer(self: ServicePersistenceHandlerImpl, restorer: Restorer): Future[void] =
  # begin restoration of all caps
  echo "registerRestorer for ", self.name
  for storedCap in self.capBySturdyRef.values:
    if storedCap.isRestoreStarted:
      storedCap.cap.ignore
      storedCap.capCompleter = newCompleter[CapServer]()
      storedCap.cap = storedCap.capCompleter.getFuture

    storedCap.isRestoreStarted = true
    storedCap.capCompleter.completeFrom(restoreUsingRestorer(storedCap, restorer))

  return now(just())

proc persist(self: ServicePersistenceHandlerImpl, storedCap: StoredCap, rgroup: ResourceGroup): Future[void] {.async.} =
  assert storedCap.description.isCompleted
  let serializedDescription = await packWithCaps(storedCap.description.get, rgroup)
  self.service.dbConn.exec(sql"insert into caps values (?, ?, ?, ?)",
                           self.name, storedCap.runtimeId, storedCap.category, encodeHex(serializedDescription))
  storedCap.persistent = true

proc addPersistentRef(self: ServicePersistenceHandlerImpl, storedCap: StoredCap, sturdyRef: string) =
  self.service.dbConn.exec(sql"insert into refs values (?, ?, ?)",
                           self.name, encodeHex(sturdyRef), storedCap.runtimeId)

proc createSturdyRef(self: ServicePersistenceHandlerImpl; rgroup: ResourceGroup;
                     description: CapDescription; persistent: bool; cap: AnyPointer): Future[MetacSturdyRef] {.async.} =
  let cap = cap.castAs(CapServer)
  let sturdyRefId = urandom(32)
  let sturdyRef = self.name & "\0" & sturdyRefId

  if description.runtimeId notin self.capByRuntimeId:
    self.capByRuntimeId[description.runtimeId] = StoredCap(description: just(description.description),
                                                           runtimeId: description.runtimeId,
                                                           category: description.category,
                                                           capCompleter: nil,
                                                           cap: just(cap))

  let storedCap = self.capByRuntimeId[description.runtimeId]
  self.capBySturdyRef[sturdyRefId] = storedCap

  if persistent:
    if description.category == nil:
      asyncRaise("cannot create persistent sturdy ref to this object")

    if not storedCap.persistent:
      await self.persist(storedCap, rgroup)

    self.addPersistentRef(storedCap, sturdyRefId)

  return MetacSturdyRef(node: self.instance.nodeAddress,
                        service: ServiceId(kind: ServiceIdKind.named, named: "persistence"),
                        objectInfo: sturdyRef.toAnyPointer)

capServerImpl(ServicePersistenceHandlerImpl, [ServicePersistenceHandler])

proc getHandlerImpl(self: PersistenceServiceImpl, serviceId: ServiceId): ServicePersistenceHandlerImpl =
  if serviceId.named notin self.handlers:
    self.handlers[serviceId.named] = ServicePersistenceHandlerImpl(
      service: self, instance: self.instance,
      name: serviceId.named,
      capByRuntimeId: newTable[string, StoredCap](),
      capBySturdyRef: newTable[string, StoredCap]())

  return self.handlers[serviceId.named]

proc getHandlerImpl(self: PersistenceServiceImpl, serviceId: string): ServicePersistenceHandlerImpl =
  return self.getHandlerImpl(ServiceId(kind: ServiceIdKind.named, named: serviceId))

proc getHandlerFor(self: PersistenceServiceImpl, serviceId: ServiceId): Future[ServicePersistenceHandler] =
  return just(self.getHandlerImpl(serviceId).asServicePersistenceHandler)

proc restore(self: PersistenceServiceImpl, objectInfo: AnyPointer): Future[AnyPointer] {.async.} =
  let objectId = objectInfo.castAs(string).split("\0", 1)
  let serviceName = objectId[0]
  let sturdyRef = objectId[1]

  let storedCap = self.handlers[serviceName].capBySturdyRef.getOrDefault(sturdyRef)
  if storedCap == nil:
    return error(AnyPointer, "invalid sturdy ref")

  let cap = await storedCap.cap
  return just(cap.toAnyPointer)

capServerImpl(PersistenceServiceImpl, [PersistenceServiceAdmin, Service, ServiceAdmin])

proc initService(instance: ServiceInstance): PersistenceServiceImpl =
  let self = PersistenceServiceImpl(handlers: newTable[string, ServicePersistenceHandlerImpl](),
                                    instance: instance,
                                    dbConn: db_sqlite.open("persistence.db", nil, nil, nil))
  self.dbConn.exec(sql"create table if not exists refs (service text, sturdyRef blob, runtimeId text, primary key (service, sturdyRef));")
  self.dbConn.exec(sql"create table if not exists caps (service text, runtimeId text, category text, description blob, primary key (service, runtimeId));")

  # drop caps without references
  self.dbConn.exec(sql"delete from caps where (select count(*) = 0 from refs where refs.runtimeId = caps.runtimeId and refs.service = caps.service)")

  for row in self.dbConn.getAllRows(sql"select service, runtimeId, category, description from caps"):
    let service = row[0]
    let runtimeId = row[1]
    let category = row[2]
    let serializedDescription = decodeHex(row[3])

    let descriptionFut = unpackWithCaps(instance, serializedDescription, AnyPointer)
    let capCompleter = newCompleter[CapServer]()
    self.getHandlerImpl(service).capByRuntimeId[runtimeId] = StoredCap(description: descriptionFut,
                                                                       runtimeId: runtimeId,
                                                                       category: category,
                                                                       persistent: true,
                                                                       cap: capCompleter.getFuture,
                                                                       capCompleter: capCompleter)

  for row in self.dbConn.getAllRows(sql"select service, sturdyRef, runtimeId  from refs"):
    let service = row[0]
    let sturdyRef = decodeHex(row[1])
    let runtimeId = row[2]
    let handler = self.getHandlerImpl(service)
    handler.capBySturdyRef[sturdyRef] = handler.capByRuntimeId[runtimeId]

  return self

proc main*() {.async.} =
  let instance = await newServiceInstance("persistence")

  let service = initService(instance).asPersistenceService

  await instance.runService(
    service=restrictInterfaces(service, Service),
    adminBootstrap=service.castAs(ServiceAdmin)
  )

when isMainModule:
  main().runMain
