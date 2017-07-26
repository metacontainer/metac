import reactor, capnp, metac/instance, metac/schemas, metac/stream, metac/persistence, metac/cli_common, strutils, collections, cligen

proc streamFromUri*(instance: Instance, uri: string): Future[Stream] {.async.} =
  return instance.restore(uri.parseSturdyRef).castAs(Stream)

proc catCmd(uri: string) =
  if uri == nil:
    quit("missing required parameter")

  asyncMain:
    let instance = await newInstance()
    let stream = await instance.restore(parseSturdyRef(uri)).castAs(Stream)
    let fd = await instance.unwrapStreamAsPipe(stream)
    asyncFor line in fd.input.lines:
      echo line.strip(leading=false)

dispatchGen(catCmd)

proc main*() =
  dispatchSubcommand({
    "cat": () => quit(dispatchCatCmd(argv, doc=""))
  })
