import metac/cli_utils, reactor, metac/desktop, metac/service_common, xrest

command("metac desktop create-for-existing", proc(display: string="", xauthority="")):
  discard

command("metac desktop create-virtual", proc()):
  let service = await getServiceRestRef("x11-desktop", X11DesktopCollection)
  let r = await service.create(X11Desktop(
    virtual: true
  ))
  echo r

command("metac desktop ls", proc()):
  let service = await getServiceRestRef("x11-desktop", X11DesktopCollection)
  let s = await service.get
  for r in s: echo r

command("metac desktop client", proc(path: string)):
  let r = await getRefForPath(path)
  let stream = r / "desktopStream"
  let (path, cleanup) = await sctpStreamAsUnixSocket(stream, "format=vnc")
  defer: cleanup()

  let p = startProcess(
    @[getHelperBinary("vncviewer"), path],
    additionalFiles = processStdioFiles,
    additionalEnv = @[("LC_ALL", "C")],
  )
  discard (await p.wait)
