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

  if runtimeId.len < 2:
    quit("ambigous ID")

  asyncMain:
    let instance = await newInstance()
    let admin = await instance.getServiceAdmin("persistence", PersistenceServiceAdmin)

    let obj = await findObjectById(admin, runtimeId)
    await admin.forgetObject(obj.service, obj.runtimeId)

dispatchGen(rmCmd)

proc mainObj*() =
  dispatchSubcommand({
    "ls": () => quit(dispatchListCmd(argv, doc="Returns list of saved references.")),
    "rm": () => quit(dispatchRmCmd(argv, doc="Forget about a saved references.")),
  })

proc mainRef*() =
  discard
