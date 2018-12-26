import xrest, metac/rest_common, metac/service_common, metac/sctpstream, reactor, collections, os, cligen, reactor/unix

proc main(url: string, bindUnixSocket="") =
  let s = url.split('?')
  var queryString = ""
  var path = s[0]
  if s.len > 1: queryString = s[1]

  asyncMain:
      var stdio: BytePipe
      if bindUnixSocket == "":
        stdio = BytePipe(
          input: createInputFromFd(0),
          output: createOutputFromFd(1)
        )
      else:
        let s = createUnixServer(bindUnixSocket)
        echo "waiting for unix connection..."
        stdio = await s.incomingConnections.receive
      
      let r = await getRefForPath(path)
      let conn = await sctpStreamClient(r, queryString)
      stderr.writeLine "connected."

      await pipe(conn, stdio)

when isMainModule:
  dispatch(main)
