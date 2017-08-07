import metac/cli_common, metac/stream, reactor/process, metac/fs_cli, posix, os

proc desktopFromUri*(instance: Instance, uri: string): Future[Desktop] {.async.} =
  let s = uri.split(":", 1)
  let schema = s[0]
  var path = s[1]

  if schema == "ref":
    return instance.restore(uri.parseSturdyRef).castAs(Desktop)
  elif schema == "localx11":
    let desktopService = await instance.getServiceAdmin("desktop", DesktopServiceAdmin)
    let display = getenv("DISPLAY")
    if display == nil:
      quit("DISPLAY environment variable missing")
    let xauthority = getenv("XAUTHORITY")
    echo "xauthority: ", xauthority
    # TODO: readonly Xauthority
    let xauthorityFile = if xauthority != nil:
                           await fileFromUri(instance, "local:" & xauthority)
                         else:
                           nullCap

    return desktopService.getDesktopForXSession(display, xauthorityFile)
  else:
    raise newException(ValueError, "invalid URI")

defineExporter(desktopExportCmd, desktopFromUri)

proc attachCmd(uri: string) =
  if uri == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let desktop = await desktopFromUri(instance, uri)
    let stream = await desktop.vncStream()

    let (fd, holder) = await instance.unwrapStream(stream)
    defer: discard close(fd)
    let process = startProcess(@[getAppDir() / "vncviewer", "127.0.0.1:1"],
                               additionalFiles = @[(cint(4), fd)],
                               additionalEnv = @[("LD_PRELOAD", getAppDir() / bindfdPath), ("CONNECT_FD", "4")])
    discard await process.wait

dispatchGen(attachCmd)

proc main*() =
  dispatchSubcommand({
    "export": () => quit(dispatchDesktopExportCmd(argv, doc="")),
    "attach": () => quit(dispatchAttachCmd(argv, doc="")),
  })
