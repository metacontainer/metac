import xrest, metac/vm, metac/fs, strutils, metac/service_common, metac/rest_common, metac/os_fs, posix, reactor/unix, reactor/process, metac/util, collections, metac/desktop, metac/media

type
  DesktopImpl* = object
    spiceSocketPath*: string
    vncSocketPath*: string

proc `desktopStream`*(self: DesktopImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  let format = req.getQueryParam("format")

  if format == "":
    raise newException(Exception, "format param missing")

  var path = ""
  if format == "vnc":
    path = self.vncSocketPath

  if format == "spice":
    path = self.spiceSocketPath

  if path == "":
    raise newException(Exception, "unsupported format ($1)" % path)

  let sock = await connectUnix(path)
  await pipe(stream, sock)

proc `get`*(self: DesktopImpl): Desktop =
  var formats: seq[DesktopFormat]
  if self.vncSocketPath != "": formats.add DesktopFormat.vnc
  if self.spiceSocketPath != "": formats.add DesktopFormat.spice

  return Desktop(supportedFormats: formats)

proc `video/get`*(self: DesktopImpl): VideoStreamInfo =
  var formats: seq[VideoStreamFormat]
  if self.vncSocketPath != "": formats.add VideoStreamFormat.vnc
  if self.spiceSocketPath != "": formats.add VideoStreamFormat.spice

  return VideoStreamInfo(supportedFormats: formats)

proc `video/videoStream`*(self: DesktopImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  await desktopStream(self, stream, req)
