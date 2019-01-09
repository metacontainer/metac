import reactor, metac/cli_utils, strformat, os, posix, metac/os_fs
import metac/desktop_x11, metac/remote_impl, metac/fs_service
import backplane_server

proc runDaemon(runBackplane: bool) {.async.} =
  var f: seq[Future[void]]

  if runBackplane:
    f.add(backplane_server.main())

    await waitForFile(getConfigDir() & "/metac/run/backplane.socket")

  f.add desktop_x11.main()
  f.add remote_impl.main()
  f.add fs_service.main()

  for fut in f: fut.onErrorQuit

  await zipVoid(f)

proc startDaemon(runBackplane: bool) =
  stderr.writeLine "Setting up systemd service for MetaContainer..."
  stderr.writeLine "(if you don't use systemd please arrange `metac daemon` command to be executed in background)"

  var cmdline = quoteShell(getAppFilename()) & " daemon --runBackplane=" & $runBackplane

  let unit = fmt"""[Unit]
Description=MetaContainer - share access to your files/desktops/USB devices securely

[Service]
Type=simple
ExecStart={cmdline}

[Install]
WantedBy=default.target
"""

  proc execCmd(cmd: string) =
    stderr.writeLine("$ " & cmd)
    discard execShellCmd(cmd)

  if getuid() == 0:
    writeFile("/etc/systemd/system/metac.service", unit)
    execCmd("systemctl daemon-reload && systemctl enable metac && systemctl start metac")
    stderr.writeLine "You can check daemon status with: `systemctl status metac`"
  else:
    let dir = getHomeDir() & "/.local/share/systemd/user/"
    createDir(dir)
    writeFile(dir & "metac-user.service", unit)
    # 'systemctl --user enable metac-user' doesn't work for some reason
    createDir(dir & "default.target.wants")
    createSymlink(dir & "metac-user.service", dir & "default.target.wants/meta-user.service")

    execCmd("systemctl --user daemon-reload && systemctl --user start metac-user")
    stderr.writeLine "You can check daemon status with: `systemctl --user status metac-user`"

command("metac daemon", proc(runBackplane=true)):
  runDaemon(runBackplane).runMain

command("metac start", proc(runBackplane=true)):
  startDaemon(runBackplane)
