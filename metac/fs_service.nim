# included from metac/fs.nim

proc main*() {.async.} =
  let instance = await newInstance(paramStr(1))

  let rootNamespace = LocalNamespace(instance: instance).asFilesystemNamespace

  let serviceAdmin = inlineCap(FilesystemServiceAdmin, FilesystemServiceAdminInlineImpl(
    rootNamespace: (() => now(just(rootNamespace)))
  ))

  let holder = await instance.thisNodeAdmin.registerNamedService(
    name="vm",
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=ServiceAdmin.createFromCap(serviceAdmin.toCapServer)
  )
  await waitForever()

when isMainModule:
  main().runMain
