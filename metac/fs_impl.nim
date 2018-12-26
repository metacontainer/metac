import xrest, metac/fs, strutils, metac/service_common, metac/rest_common, metac/os_fs, posix, reactor/unix, reactor/process

type
  FileImpl* = ref object
    path*: string

  FsImpl* = ref object
    path*: string

proc open(self: FileImpl, readonly=false): Future[cint] =
  echo "open ", self.path
  return openAt(self.path, finalFlags=if readonly: O_RDONLY else: O_RDWR)

proc nbdConnection*(f: FileImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  let readonly = req.getQueryParam("readonly") == "1"
  let fd = await f.open(readonly=readonly)

  let files = @[(0.cint, 0.cint), (1.cint, 1.cint), (2.cint, 2.cint), (3.cint, fd)]
  let (dirPath, cleanup) = createUnixSocketDir()
  let socketPath = dirPath & "/socket"
  var cmd = @["qemu-nbd",
              "--format=raw",
              "--discard=on", # enable discard/TRIM
              #"--export-name=default",
              "/proc/self/fd/3", "--socket=" & socketPath]
  if readonly: cmd.add "--read-only"

  defer: cleanup()

  let gid: uint32 = 0
  let uid: uint32 = 0
  let process = startProcess(
    cmd,
    additionalFiles=files, uid=uid, gid=gid)

  echo "started ", cmd
  await waitForFile(socketPath)

  let sock = await connectUnix(socketPath)
  await pipe(stream, sock)
  discard (await process.wait)

proc data*(f: FileImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  let fd = await f.open(readonly=true)
  let f = createInputFromFd(fd)
  await pipe(f, stream)

  await asyncSleep(2000) # TODO: we need sctp_drain on something

proc sftpConnection*(f: FsImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  discard

when isMainModule:
  discard
