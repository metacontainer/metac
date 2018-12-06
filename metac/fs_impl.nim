import xrest, metac/fs, strutils, metac/service_common, metac/rest_common, metac/os_fs, posix, reactor/unix, reactor/process

type
  FileImpl* = ref object
    path*: string

  FsImpl* = ref object
    path*: string

proc open(self: FileImpl): Future[cint] =
  return openAt(self.path, finalFlags=O_RDWR)

proc nbdConnection*(f: FileImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  let fd = await f.open
  setBlocking(fd)

  let files = @[(1.cint, 1.cint), (2.cint, 2.cint), (3.cint, fd)]
  let (dirPath, cleanup) = createUnixSocketDir()
  let socketPath = dirPath & "/socket"
  var cmd = @["qemu-nbd",
              "-f", "raw",
              "/proc/self/fd/3", "--socket=" & socketPath]

  defer: cleanup()

  let gid: uint32 = 0
  let uid: uint32 = 0
  let process = startProcess(
    cmd,
    additionalFiles=files, uid=uid, gid=gid)

  await waitForFile(socketPath)

  let sock = await connectUnix(socketPath)
  await pipe(stream, sock)
  discard (await process.wait)

proc data*(f: FileImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  let fd = await f.open
  let f = createInputFromFd(fd)
  defer: f.recvClose
  await pipe(f, stream)

proc sftpConnection*(f: FsImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  discard

when isMainModule:
  discard
