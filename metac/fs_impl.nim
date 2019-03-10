import xrest, metac/fs, strutils, metac/service_common, metac/rest_common, metac/os_fs, posix, reactor/unix, reactor/process

type
  FileImpl* = ref object
    path*: string

  FsImpl* = ref object
    path*: string

proc open(self: FileImpl, readonly=false): Future[cint] =
  echo "open ", self.path
  return openAt(self.path, finalFlags=if readonly: O_RDONLY else: O_RDWR)

proc nbdAttach*(f: FileImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  discard

proc doMountBlock*(f: BlockDevMount, path: string) {.async.} =
  discard

proc nbdConnection*(f: FileImpl, stream: SctpConn, req: HttpRequest) {.async.} =
  let readonly = req.getQueryParam("readonly") == "1"
  let fd = await f.open(readonly=readonly)

  let files = @[(0.cint, 0.cint), (1.cint, 1.cint), (2.cint, 2.cint), (3.cint, fd)]
  let (dirPath, cleanup) = createUnixSocketDir()
  let socketPath = dirPath & "/socket"
  var cmd = @[getHelperBinary("qemu-nbd"),
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
  await pipe(f, stream, close=true)

  # wait until SCTP connection is closed for good
  discard (tryAwait stream.sctpPackets.input.receive)

proc get*(f: FsImpl): Filesystem =
  return Filesystem(path: f.path)

proc listingSync(path: string): FsListing =
  var d = opendir(path)
  if d == nil: return FsListing(isAccessible: false)

  var items: seq[FileEntry]

  while true:
    var x = readdir(d)
    if x == nil: break

    let name = $cast[cstring](addr x.d_name)
    if name == "." or name == "..": continue

    items.add(FileEntry(name: name, isDirectory: x.d_type == DT_DIR))

    if items.len > 100_0000:
      raise newException(Exception, "directory too large to list")

  return FsListing(isAccessible: true, entries: items)

proc listing*(f: FsImpl): Future[FsListing] =
  let path = f.path
  return spawn(listingSync(path))

proc sftpConnection*(f: FsImpl, conn: SctpConn, req: HttpRequest) {.async.} =
  let dirFd = await openAt(f.path)
  defer: discard close(dirFd)
  let process = startProcess(
    @[getHelperBinary("sftp-server"),
      "-e", # stderr instead of syslog
      "-C", "4", # chroot to
      #"-U", $(fs.info.uid), # setuid
    ],
    pipeFiles=[0.cint, 1.cint], additionalFiles=[(2.cint, 2.cint),(4.cint, dirFd)])

  await pipeStdio(conn, process)

proc doMount*(f: FilesystemRef, path: string) {.async.} =
  assert path[0] == '/'

  let conn = await f.sftpConnection

  var opt = "slave"
  # if getuid() == 0:
  #   opt &= ",allow_other,default_permissions"
  # if info.exclusive:
  #   opt &= ",kernel_cache,entry_timeout=1000000,attr_timeout=1000000,cache_timeout=1000000"

  let process = startProcess(@[getHelperBinary("sshfs"),
                               "-f", # foreground
                               "-o", opt,
                               "metacfs:", path],
                             additionalFiles= @[(2.cint, 2.cint)],
                             pipeFiles= @[0.cint, 1.cint])

  await pipeStdio(conn, process)

proc doUmount*(path: string) {.async.} =
  # TODO: do lazy umount with -z?
  let process = startProcess(@["fusermount", "-u", path], additionalFiles = processStdioFiles)
  discard (await process.wait)

when isMainModule:
  discard
