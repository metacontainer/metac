import reactor, metac/cli_utils
import metac/desktop_x11, metac/remote_impl, metac/fs_service
import backplane_server

proc runDaemon(runBackplane: bool) =
  let f = @[
    desktop_x11.main(),
    remote_impl.main(),
    fs_service.main()
  ]
  if runBackplane:
    discard

  for fut in f: fut.onErrorQuit

  zipVoid(f).runMain

command("metac daemon", proc(runBackplane=false)):
  runDaemon(runBackplane)
