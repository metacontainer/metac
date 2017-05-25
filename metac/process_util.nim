import reactor, reactor/process, strutils

proc execCmd*(command: seq[string], raiseOnError=true): Future[void] {.async.} =
  let process = startProcess(command=command, additionalFiles= @[(1.cint, 1.cint), (2.cint, 2.cint)])
  let code = await process.wait
  if code != 0 and raiseOnError:
    asyncRaise("process $1 returned error code" % ($command))
