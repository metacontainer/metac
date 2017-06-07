import metac, metac/schemas, collections

proc main*() {.async.} =
  let instance = await newInstance()
  let launcher = await instance.getServiceAdmin("computevm", ComputeLauncher)

  let config = ProcessEnvironmentDescription(
    memory: 512,
    filesystems: @[],
    networks: @[]
  )

  let env = await launcher.launch(nil, config)

when isMainModule:
  main().runMain
