import metac, metac/schemas, metac/fs_cli, metac/network_cli, collections, metac/stream

proc main*() {.async.} =
  let instance = await newInstance()
  let launcher = await instance.getServiceAdmin("computevm", ComputeLauncher)
  let dir = await fsFromUri(instance, "local:/bin")
  let myNet = await netFromUri(instance, "newlocal:processnet")

  let config = ProcessEnvironmentDescription(
    memory: 512,
    filesystems: @[
      FsMount(path: "/bin", fs: dir)
    ],
    networks: @[NetworkInterface(l2interface: myNet,
                                 addresses: @["10.50.0.2/24"])]
  )

  let processConfig = ProcessDescription(
    args: @["/bin/busybox", "sh", "-c", "echo hello hello hello hello; ls /bin; cat /proc/mounts"],
    files: @[FD(targets: @[uint32(0)]), FD(targets: @[uint32(1)])]
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
