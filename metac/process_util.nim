import reactor, reactor/unix, reactor/process, strutils, os, posix

proc execCmd*(command: seq[string], raiseOnError=true): Future[void] {.async.} =
  let process = startProcess(command=command, additionalFiles= @[(1.cint, 1.cint), (2.cint, 2.cint)])
  let code = await process.wait
  if code != 0 and raiseOnError:
    asyncRaise("process $1 returned error code" % ($command))

proc systemdNotify*(msg: string) {.async.} =
  let socket = getEnv("NOTIFY_SOCKET")
  if socket != "":
    var un: SockAddr_un
    un.sun_family = AF_UNIX
    doAssert(socket.len < sizeof(un.sun_path) - 1)

    copyMem(addr un.sun_path[0], socket.cstring, socket.len + 1)

    if un.sun_path[0] == '@':
      un.sun_path[0] = '\0'

    let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
    doAssert(fd.int != 0)
    discard sendto(fd, msg.cstring, msg.len, MSG_NOSIGNAL, cast[ptr SockAddr](addr un), sizeof(un).Socklen)
    discard close(fd)

proc systemdNotifyReady*() {.async.} =
  await systemdNotify("READY=1")
