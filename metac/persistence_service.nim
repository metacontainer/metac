import tables, reactor, capnp, caprpc, strutils, metac/schemas, metac/instance, collections, db_sqlite, metac/persistence, os

type
  PersistenceServiceImpl = ref object of RootObj
    instance: Instance
    handlers: TableRef[string, ServicePersistenceHandlerImpl]
    dbConn: DbConn

  StoredCap = ref object
    instance: Instance
    service: PersistenceServiceImpl
    stopped: bool
    serviceName: string
    refs: seq[string]

    runtimeId: string
    category: string
    persistent: bool
    serializedDescription: string # present if persistent == true
    description: AnyPointer # present if persistent == false
    summary: string

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

proc forget(self: StoredCap) {.async.} =
  if self.stopped:
    return

  echo "fogetting about ", self.category

  self.stopped = true
  self.cap = error(CapServer, "cap removed")
  self.capCompleter = nil
  self.description = nil

  if self.serviceName in self.service.handlers:
    let handler = self.service.handlers[self.serviceName]
    for sturdyRef in self.refs:
      handler.capBySturdyRef.del sturdyRef

    handler.capByRuntimeId.del self.runtimeId

  if not self.retryRestore.getFuture.isCompleted:
    self.retryRestore.complete

proc capRestoreThread(self: StoredCap) {.async.} =
  var consecutiveFailureCount = 0
  var firstIteration = true
  while not self.stopped:
    var obj: Result[CapServer]
    if firstIteration and self.cap.isCompleted: # ref just created
      obj = self.cap.getResult
    else:
      echo "restoring..."
      obj = tryAwait restoreUsingRestorer(self)
      echo self.category, " capability restore returned"

    firstIteration = false

    if self.cap.isCompleted:
      self.capCompleter = newCompleter[CapServer]()
      self.cap = self.capCompleter.getFuture

    self.capCompleter.completeFrom(obj)
    self.cap.ignore # to display error message, if needed

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

    if not self.persistent:
      # we do not retry restore
      await self.forget
      return

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
  self.service.dbConn.exec(sql"insert into caps values (?, ?, ?, ?, ?)",
                           self.name, storedCap.runtimeId, storedCap.category, encodeHex(storedCap.serializedDescription), storedCap.summary)
  storedCap.persistent = true

proc addPersistentRef(self: ServicePersistenceHandlerImpl, storedCap: StoredCap, sturdyRef: string) =
  self.service.dbConn.exec(sql"insert into refs values (?, ?, ?)",
                           self.name, encodeHex(sturdyRef), storedCap.runtimeId)

proc createSturdyRef(self: ServicePersistenceHandlerImpl; rgroup: ResourceGroup;
                     description: CapDescription; persistent: bool; cap: AnyPointer): Future[MetacSturdyRef] {.async.} =
  let cap = cap.castAs(CapServer)
  let sturdyRefId = urandom(16)
  let sturdyRef = self.name & "\0" & sturdyRefId

  if description.runtimeId notin self.capByRuntimeId:
    let summary = await cap.castAs(Persistable).summary
    self.capByRuntimeId[description.runtimeId] = StoredCap(
      serviceName: self.name,
      service: self.service, instance: self.service.instance,
      refs: @[],
      description: description.description,
      summary: summary,
      runtimeId: description.runtimeId,
      category: description.category,
      capCompleter: nil,
      isRestoreStarted: true,
      cap: just(cap),
      retryRestore: newCompleter[void]())

    capRestoreThread(self.capByRuntimeId[description.runtimeId]).ignore

  let storedCap = self.capByRuntimeId[description.runtimeId]
  self.capBySturdyRef[sturdyRefId] = storedCap
  storedCap.refs.add sturdyRefId

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

proc listObjects(self: PersistenceServiceImpl): Future[seq[PersistentObjectInfo]] {.async.} =
  return @[]

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
  self.dbConn.exec(sql"create table if not exists caps (service text, runtimeId text, category text, description blob, summary text, primary key (service, runtimeId));")

  # drop caps without references
  self.dbConn.exec(sql"delete from caps where (select count(*) = 0 from refs where refs.runtimeId = caps.runtimeId and refs.service = caps.service)")

  for row in self.dbConn.getAllRows(sql"select service, runtimeId, category, description, summary from caps"):
    let service = row[0]
    let runtimeId = row[1]
    let category = row[2]
    let serializedDescription = decodeHex(row[3])
    let summary = row[4]

    let capCompleter = newCompleter[CapServer]()
    self.getHandlerImpl(service).capByRuntimeId[runtimeId] = StoredCap(
      service: self, serviceName: service,
      instance: instance, serializedDescription: serializedDescription,
      runtimeId: runtimeId,
      category: category,
      persistent: true,
      refs: @[],
      cap: capCompleter.getFuture,
      capCompleter: capCompleter,
      summary: summary,
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
