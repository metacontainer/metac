import xrest, metac/rest_common, metac/service_common, metac/sctpstream, reactor, collections, os

proc main(url: string) {.async.} =
  let s = url.split('?')
  var queryString = ""
  var path = s[0]
  if s.len > 1: queryString = s[1]

  let r = await getRefForPath(path)
  let conn = await sctpStreamClient(r, queryString)
  stderr.writeLine "connected."
  let stdio = BytePipe(
    input: createInputFromFd(0),
    output: createOutputFromFd(1)
  )
  await pipe(conn, stdio)

when isMainModule:
  main(paramStr(1)).runMain
