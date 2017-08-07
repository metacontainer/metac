import reactor, caprpc, capnp, metac/schemas, metac/instance, metac/persistence, metac/stream, os, posix, collections, reactor/process, metac/fs

type
  X11Desktop = ref object of PersistableObj
    instance: ServiceInstance
    address: string
    xauthority: schemas.File

    serverRunning: bool
    serverStream: schemas.Stream
    serverProcess: process.Process

  DesktopServiceImpl = ref object of PersistableObj
    instance: ServiceInstance

const x0vncserverPath {.strdefine.} = "x0vncserver"

proc vncStream(self: X11Desktop): Future[Stream] {.async.} =
  if self.serverRunning:
    return self.serverStream

  let (serverFd, stream, cleanup) = wrapUnixServerFdAsStream(self.instance)
  self.serverRunning = true
  self.serverStream = stream
  let display = self.address
  var xauthorityPath: string
  if self.xauthority.isNullCap:
    xauthorityPath = ""
  else:
    xauthorityPath = await copyToTempFile(self.instance, self.xauthority, sizeLimit=1024*16)

  defer: discard close(serverFd)
  self.serverProcess =
    startProcess(@[getAppDir() / x0vncserverPath, "-SecurityTypes", "none", "-rfbport", "1"],
                 additionalFiles = @[(4.cint, serverFd)],
                 additionalEnv = @[("BIND_FD", "4"),
                                   ("LD_PRELOAD", getAppDir() / bindfdPath),
                                   ("DISPLAY", display),
                                   ("XAUTHORITY", xauthorityPath)])

  let finish = bindOnlyVars([xauthorityPath, cleanup], proc(code: int) =
    removeFile(xauthorityPath)
    cleanup())

  self.serverProcess.wait.then(finish).ignore

  return stream

proc summary(self: X11Desktop): Future[string] {.async.} =
  return self.address

capServerImpl(X11Desktop, [Desktop, Persistable, Waitable])

proc destroyDesktop(self: X11Desktop) =
  if self.serverProcess != nil:
    self.serverProcess.kill()

proc getDesktopForXSession(self: DesktopServiceImpl, address: string, xauthority: schemas.File): Future[Desktop] {.async.} =
  # TODO: check if display is accessible
  var desktop: X11Desktop
  new(desktop, destroyDesktop)
  desktop.instance = self.instance
  desktop.address = address
  desktop.xauthority = xauthority
  desktop.persistenceDelegate = makePersistenceDelegate(self.instance,
                                                        "desktop:x11",
                                                        description=DesktopServiceAdmin_getDesktopForXSession_Params(address: address, xauthority: xauthority).toAnyPointer)

  return desktop.asDesktop

capServerImpl(DesktopServiceImpl, [DesktopServiceAdmin])

proc main*() {.async.} =
  enableGcNoDelay()

  let instance = await newServiceInstance("desktop")
  let serviceAdmin = DesktopServiceImpl(instance: instance)

  proc restorer(d: CapDescription): Future[AnyPointer] {.async.} =
    case d.category:
      of "desktop:x11":
        return
      else:
        asyncRaise "unknown category"

  await instance.registerRestorer(restorer)

  await instance.runService(
    service=Service.createFromCap(nothingImplemented),
    adminBootstrap=ServiceAdmin.createFromCap(serviceAdmin.asDesktopServiceAdmin.toCapServer)
  )
