import xrest, metac/fs, strutils, metac/service_common, metac/rest_common, metac/flatdb, metac/desktop, tables, posix, collections, metac/os_fs, reactor/unix, metac/media, osproc, reactor

type
  X11DesktopImpl = ref object
    info: X11Desktop
    serverProcess: reactor.Process
    cleanupProcs: seq[proc()]
    vncSocketPath: string

  X11DesktopService = ref object
    desktops: Table[string, X11DesktopImpl]
    db: FlatDB

proc makeDesktopId(): string =
  var id = 100
  while true:
    let path = "/tmp/.X11-unix/X" & ($id)
    var s: Stat
    if stat(path, s) == 0:
      id += 1
      continue

    return $id

proc `item/desktop/desktopStream`(self: X11DesktopService, id: string, stream: SctpConn, req: HttpRequest) {.async.} =
  let format = req.getQueryParam("format")
  if format != "vnc":
    raise newException(Exception, "unsupported format")

  let sock = await connectUnix(self.desktops[id].vncSocketPath)
  await pipe(stream, sock)

proc `item/desktop/get`(self: X11DesktopService, id: string): Desktop =
  return Desktop(supportedFormats: @[DesktopFormat.vnc])

proc `item/desktop/video/get`(self: X11DesktopService, id: string): VideoStreamInfo =
  return VideoStreamInfo(supportedFormats: @[VideoStremaFormat.vnc])

proc `item/desktop/video/videoStream`(self: X11DesktopService, id: string, stream: SctpConn, req: HttpRequest) {.async.} =
  await `item/desktop/desktopStream`(self, id, stream, req)

proc runDesktop(self: X11DesktopService, desktop: X11DesktopImpl) =
  let (socketDir, cleanup) = createUnixSocketDir()

  desktop.cleanupProcs.add(cleanup)
  desktop.vncSocketPath = socketDir / "socket"

  # Note: rfbunixpath implies no TCP/IP, so it's safe to use '-SecurityTypes none'
  if desktop.info.virtual:
    desktop.info.displayId = some(makeDesktopId())
    desktop.info.xauthorityPath = some(getenv("HOME") / ".Xauthority")

    let xauthority = desktop.info.xauthorityPath.get
    let displayId = ":" & desktop.info.displayId.get
    discard execProcess("xauth", @["-f", xauthority, "remove", displayId], options={poUsePath})
    discard execProcess("xauth", @["-f", xauthority, "add", displayId, "MIT-MAGIC-COOKIE-1", hexUrandom(16)], options={poUsePath})
    desktop.serverProcess = startProcess(
      @[getHelperBinary("Xvnc"), displayId,
        "-auth", xauthority,
        "-SecurityTypes", "none", "-rfbunixpath", socketDir / "socket"])
  else:
    desktop.serverProcess = startProcess(
      @[getHelperBinary("x0vncserver"),
        "-SecurityTypes", "none", "-rfbunixpath", desktop.vncSocketPath],
      additionalEnv = @[("DISPLAY", desktop.info.displayId.get),
                        ("XAUTHORITY", desktop.info.xauthorityPath.get)])

proc create(self: X11DesktopService, info: X11Desktop): X11DesktopRef =
  var info = info
  let id = hexUrandom()
  let desktop = X11DesktopImpl(info: info)

  self.desktops[id] = desktop

  self.runDesktop(desktop)

  return makeRef(X11DesktopRef, id)

proc get(self: X11DesktopService): seq[X11DesktopRef] =
  return toSeq(self.desktops.keys).mapIt(makeRef(X11DesktopRef, it))

proc `item/get`(self: X11DesktopService, id: string): X11Desktop =
  return self.desktops[id].info

proc main*() {.async.} =
  let s = X11DesktopService(
    desktops: initTable[string, X11DesktopImpl](),
  )

  #for id in s.:
  #  startMounter(s, id).ignore

  let handler = restHandler(X11DesktopCollection, s)
  await runService("x11-desktop", handler)

when isMainModule:
  main().runMain
