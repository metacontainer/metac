import os, reactor, caprpc, metac/instance, metac/schemas

type
  VMServiceImpl = ref object of RootObj

proc getPinnedVMs(self: VMServiceImpl): Future[seq[VM]] {.async.} =
  return nil

proc getPciDevices(self: VMServiceImpl): Future[seq[PciDevice]] {.async.} =
  return nil

proc getLauncher(self: VMServiceImpl): Future[VMLauncher] {.async.} =
  return VMLauncher.createFromCap(nothingImplemented)

proc toCapServer(obj: VMServiceImpl): CapServer =
  discard # TODO

proc main() {.async.} =
  let instance = await newInstance(paramStr(1))

  let serviceAdmin = VMServiceImpl().asVMServiceAdmin

  let holder = await instance.thisNodeAdmin.registerNamedService(
    name="vm",
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=ServiceAdmin.createFromCap(nothingImplemented)
  )
  await asyncSleep(3000)

when isMainModule:
  main().runMain()
