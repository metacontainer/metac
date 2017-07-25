import tables, reactor, capnp, caprpc, strutils, metac/schemas, metac/instance, collections, db_sqlite, metac/persistence, os

type
  PersistenceServiceImpl = ref object of RootObj
    instance: Instance
    handlers: TableRef[string, ServicePersistenceHandlerImpl]
    dbConn: DbConn

  StoredCap = ref object
    instance: Instance

    runtimeId: string
    category: string
    persistent: bool
    serializedDescription: string # present if persistent == true
    description: AnyPointer # present if persistent == false

    restorer: Restorer

    cap: Future[CapServer]
    capCompleter: Completer[CapServer]
    retryRestore: Completer[void] # when this completes, restore should be retried
    isRestoreStarted: bool

  ServicePersistenceHandlerImpl = ref object of RootObj
    service: PersistenceServiceImpl
    instance: Instance
    name: string

    capByRuntimeId: TableRef[string, StoredCap]
    capBySturdyRef: TableRef[string, StoredCap]

proc restoreInternal(self: StoredCap, description: AnyPointer): Future[CapServer] {.async.} =
  if self.category == "persistence:call":
    let callDescr = description.castAs(Call)
    let retStruct = await callDescr.cap.castAs(CapServer).call(callDescr.interfaceId, callDescr.methodId, callDescr.args)
    return retStruct.getPointerField(0).castAs(CapServer)
  else:
    raise newException(ValueError, "bad category")

proc getDescription(self: StoredCap): Future[AnyPointer] {.async.} =
  if self.persistent:
    return unpackWithCaps(self.instance, self.serializedDescription, AnyPointer)
  else:
    return self.description

proc restoreUsingRestorer(self: StoredCap): Future[CapServer] {.async.} =
  let description = await self.getDescription
  if self.category.startsWith("persistence:"):
    return restoreInternal(self, description)
  else:
    return self.restorer.restoreFromDescription(CapDescription(category: self.category, runtimeId: self.runtimeId, description: description)).castAs(CapServer)

proc capRestoreThread(self: StoredCap) {.async.} =
  var consecutiveFailureCount = 0
  while true:
    echo "restoring..."
    let obj = tryAwait restoreUsingRestorer(self)
    echo self.category, " capability restore returned"

    if self.cap.isCompleted:
      self.capCompleter = newCompleter[CapServer]()
      self.cap = self.capCompleter.getFuture

    self.capCompleter.completeFrom(obj)
    self.cap.ignore # to display error message, if needed

    if not self.persistent:
      # we do not retry restore
      return

    if obj.isSuccess:
      # we shall wait until restored capability fails
      consecutiveFailureCount = 0
      let value = obj.get
      let waitFut = value.castAs(Waitable).wait()
      waitFut.ignore
      discard (tryAwait waitFut)
      echo self.category, " capability failed (reason: ", waitFut, ")"

      self.capCompleter = newCompleter[CapServer]()
      self.cap = self.capCompleter.getFuture

    consecutiveFailureCount += 1

    # wait some timeout or until we are awaken
    let sleepTime = 100 shl min(consecutiveFailureCount, 9)
    echo self.capCompleter, " sleeping ", sleepTime, " ms"
    await asyncSleep(sleepTime) or self.retryRestore.getFuture

    self.retryRestore = newCompleter[void]()

proc registerRestorer(self: ServicePersistenceHandlerImpl, restorer: Restorer): Future[void] =
  # begin restoration of all caps
  echo "registerRestorer for ", self.name

  for storedCap in self.capBySturdyRef.values:
    storedCap.restorer = restorer

    if storedCap.isRestoreStarted:
      if not storedCap.retryRestore.getFuture.isCompleted:
        storedCap.retryRestore.complete
    else:
      storedCap.isRestoreStarted = true
      capRestoreThread(storedCap).ignore

  return now(just())

proc persist(self: ServicePersistenceHandlerImpl, storedCap: StoredCap, rgroup: ResourceGroup): Future[void] {.async.} =
  storedCap.serializedDescription = await packWithCaps(storedCap.description, rgroup)
  storedCap.description = nil
  self.service.dbConn.exec(sql"insert into caps values (?, ?, ?, ?)",
                           self.name, storedCap.runtimeId, storedCap.category, encodeHex(storedCap.serializedDescription))
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
    self.capByRuntimeId[description.runtimeId] = StoredCap(description: description.description,
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
  let path = if existsEnv("METAC_PERSISTENCE_DB"):
               getEnv("METAC_PERSISTENCE_DB")
             else:
               "/var/lib/metac/persistence.db"
  createDir(splitPath(path).head)
  let self = PersistenceServiceImpl(handlers: newTable[string, ServicePersistenceHandlerImpl](),
                                    instance: instance,
                                    dbConn: db_sqlite.open(path, nil, nil, nil))
  self.dbConn.exec(sql"create table if not exists refs (service text, sturdyRef blob, runtimeId text, primary key (service, sturdyRef));")
  self.dbConn.exec(sql"create table if not exists caps (service text, runtimeId text, category text, description blob, primary key (service, runtimeId));")

  # drop caps without references
  self.dbConn.exec(sql"delete from caps where (select count(*) = 0 from refs where refs.runtimeId = caps.runtimeId and refs.service = caps.service)")

  for row in self.dbConn.getAllRows(sql"select service, runtimeId, category, description from caps"):
    let service = row[0]
    let runtimeId = row[1]
    let category = row[2]
    let serializedDescription = decodeHex(row[3])

    let capCompleter = newCompleter[CapServer]()
    self.getHandlerImpl(service).capByRuntimeId[runtimeId] = StoredCap(
      instance: instance, serializedDescription: serializedDescription,
      runtimeId: runtimeId,
      category: category,
      persistent: true,
      cap: capCompleter.getFuture,
      capCompleter: capCompleter,
      retryRestore: newCompleter[void]())

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
