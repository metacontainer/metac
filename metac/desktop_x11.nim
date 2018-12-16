import xrest, metac/fs, strutils, metac/service_common, metac/rest_common, metac/flatdb, metac/desktop, tables, posix, collections, metac/os_fs, reactor/unix, metac/media, osproc

type
  X11DesktopImpl = ref object
    info: X11Desktop
    serverProcess: Process
    cleanupProcs: seq[proc()]
    vncSocketPath: string

  X11DesktopService = ref object
    desktops: Table[string, X11DesktopImpl]

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

proc create(self: X11DesktopService, info: X11Desktop): X11DesktopRef =
  var info = info
  let id = hexUrandom()
  let desktop = X11DesktopImpl(info: info)

  let (socketDir, cleanup) = createUnixSocketDir()

  desktop.cleanupProcs.add(cleanup)
  desktop.vncSocketPath = socketDir / "socket"

  self.desktops[id] = desktop

  # Note: rfbunixpath implies no TCP/IP, so it's safe to use '-SecurityTypes none'

  if info.virtual:
    assert info.displayId.isNone and info.xauthorityPath.isNone
    let displayId = makeDesktopId()
    info.displayId = some(displayId)
    let xauthority = getenv("HOME") / ".Xauthority"
    info.xauthorityPath = some(xauthority)
    # delete old one?
    discard execProcess("xauth", @["-f", xauthority, "add", "MIT-MAGIC-COOKIE-1", hexUrandom(16)])
    desktop.serverProcess = startProcess(
      @[getHelperBinary("Xvnc"), ":" & displayId,
        "-auth", xauthority,
        "-SecurityTypes", "none", "-rfbunixpath", socketDir / "socket"])
  else:
    desktop.serverProcess = startProcess(
      @[getHelperBinary("x0vncserver"),
        "-SecurityTypes", "none", "-rfbunixpath", socketDir / "socket"],
      additionalEnv = @[("DISPLAY", info.displayId.get),
                        ("XAUTHORITY", info.xauthorityPath.get)])

  return makeRef(X11DesktopRef, "./" & id)

proc get(self: X11DesktopService): seq[X11DesktopRef] =
  return toSeq(self.desktops.keys).mapIt(makeRef(X11DesktopRef, it))

proc `item/get`(self: X11DesktopService, id: string): X11Desktop =
  return self.desktops[id].info

proc main() {.async.} =
  let s = X11DesktopService(
    desktops: initTable[string, X11DesktopImpl](),
  )
  # TODO: restore persistent desktops
  let handler = restHandler(X11DesktopCollection, s)
  await runService("x11-desktop", handler)

when isMainModule:
  main().runMain
