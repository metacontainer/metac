import metac, metac/schemas, metac/fs_cli, collections, metac/stream

proc main*() {.async.} =
  let instance = await newInstance()
  let launcher = await instance.getServiceAdmin("computevm", ComputeLauncher)
  let dir = await fsFromUri(instance, "local:/bin")

  let config = ProcessEnvironmentDescription(
    memory: 512,
    filesystems: @[
      FsMount(path: "/bin", fs: dir)
    ],
    networks: @[]
  )

  let processConfig = ProcessDescription(
    args: @["/bin/busybox", "sh", "-c", "echo hello hello hello hello; ls /bin; cat /proc/mounts"],
    files: @[FD(), FD()]
  )

  let r = await launcher.launch(processConfig, config)
  let (env, process) = (r.env, r.process)

  # read from stdout
  let stdout = await process.file(1)
  let pipe = await instance.unwrapStreamAsPipe(stdout)
  asyncFor line in pipe.input.lines:
    echo "[out]", line.strip(leading=true)

when isMainModule:
  main().runMain
