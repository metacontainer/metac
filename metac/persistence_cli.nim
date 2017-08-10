import metac/cli_common

proc listCmd() =
  asyncMain:
    let instance = await newInstance()
    let admin = instance.getServiceAdmin("persistence", PersistenceServiceAdmin)
    let objects = await admin.listObjects

    var table: seq[seq[string]] = @[]

    for obj in objects:
      table.add(@[
        obj.service,
        obj.category,
        if obj.persistent: "persist" else: "",
        obj.runtimeId[0..<8],
        obj.summary
      ])

    renderTable(table)

dispatchGen(listCmd)

proc findObjectById(admin: PersistenceServiceAdmin, runtimeId: string): Future[PersistentObjectInfo] {.async.} =
  let objects = await admin.listObjects

  var matching: seq[PersistentObjectInfo] = @[]

  if runtimeId.len < 2:
    quit("ambigous ID")

  for obj in objects:
    if obj.runtimeId.startsWith(runtimeId): matching.add obj

  if matching.len == 0:
    quit("object not found")

  if matching.len > 1:
    quit("ambigous ID")

  return matching[0]

proc rmCmd(runtimeId: string) =
  if runtimeId == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let admin = await instance.getServiceAdmin("persistence", PersistenceServiceAdmin)

    let obj = await findObjectById(admin, runtimeId)
    await admin.forgetObject(obj.service, obj.runtimeId)

dispatchGen(rmCmd)

proc mainObj*() =
  dispatchSubcommand({
    "ls": () => quit(dispatchListCmd(argv, doc="Returns list of saved objects.")),
    "rm": () => quit(dispatchRmCmd(argv, doc="Forget about a saved object.")),
  })

proc listRefCmd(runtimeId: string) =
  if runtimeId == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let admin = await instance.getServiceAdmin("persistence", PersistenceServiceAdmin)
    #let objects = await admin.listObjects

    let obj = await findObjectById(admin, runtimeId)
    let refs = await admin.listReferences(obj.service, obj.runtimeId)
    var table: seq[seq[string]] = @[]

    for reference in refs:
      table.add(@[reference.sturdyRef.formatSturdyRef])

    renderTable(table)

dispatchGen(listRefCmd)

proc mainRef*() =
  dispatchSubcommand({
    "ls": () => quit(dispatchListRefCmd(argv, doc="Returns list of references to a given object.")),
  })
