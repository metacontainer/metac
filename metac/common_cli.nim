import metac/cli_common

proc destroyCmd(uri: string) =
  if uri == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let obj = await instance.restore(uri.parseSturdyRef).castAs(Destroyable)
    await obj.destroy

dispatchGen(destroyCmd)

proc mainDestroy*() =
  dispatchDestroyCmd(argv, doc="Destroy any destroyable object pointed by [uri].").quit
