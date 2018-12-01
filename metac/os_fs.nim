import strutils, posix, os, reactor/syscall, reactor/threading, reactor

proc checkValidPath(path: string) =
  if path.len >= 1024:
    raise newException(Exception, "path too long")

  for ch in path:
    if ch == '\0':
      raise newException(Exception, "path cannot contain null bytes")

proc safeJoin*(base: string, child: string): string =
  # Safely join `base` and `child` paths - it guarantees that the resulting
  # path will be inside `base`.
  # Here we asume that the filesystem is sane (e.g. probably not Mac OSX)
  checkValidPath(base)
  checkValidPath(child)

  if base == "/" and child == "/":
    return "/"

  if child.split('/').len + base.split('/').len > 40:
    raise newException(ValueError, "path too long")

  var base = base.strip(leading=false, chars={'/'})

  for item in child.strip(chars={'/'}).split('/'):
    if item == ".." or item == "." or item == "":
      raise newException(ValueError, "invalid path component " & item)
    base &= "/" & item

  return base

proc openat(dirfd: cint, pathname: cstring, flags: cint, mode: cint): cint {.importc, header: "<fcntl.h>".}
var O_CLOEXEC {.importc, header: "<fcntl.h>"}: cint
var O_NOFOLLOW {.importc, header: "<fcntl.h>"}: cint
var O_DIRECTORY {.importc, header: "<fcntl.h>"}: cint

proc openAtSync(path: string, finalFlags: cint): cint =
  checkValidPath(path)
  var parts = path[1..^1].split('/')
  var fd: cint = retrySyscall(open("/", O_DIRECTORY or O_NOFOLLOW or O_CLOEXEC, 0o400))
  defer: discard close(fd)

  for i in 0..<parts.len:
    if parts[i] == "." or parts[i] == ".." or parts[i] == "":
      raise newException(ValueError, "invalid path component " & parts[i])
    var flags = if i == parts.len - 1: finalFlags else: O_DIRECTORY
    flags = flags or O_NOFOLLOW or O_CLOEXEC
    let newFd = retrySyscall(openat(fd, parts[i], flags, 0o400))
    discard close(fd)
    fd = newFd

  result = fd
  fd = -1

proc openAt*(path: string, finalFlags: cint=O_DIRECTORY): Future[cint] =
  # Open file at `path` without following symlinks.
  assert path != nil and path.len > 0 and path[0] == '/'
  return spawn(openAtSync(path, finalFlags))

proc createDirUnreadable*(path: string) =
  let (head, tail) = path.strip(chars={'/'}, leading=false).splitPath
  createDir(head)
  let err = mkdir(path, 0o700)
  discard chmod(path, 0o700)
  if err < 0 and errno != EEXIST:
    raiseOSError(osLastError())

proc mkdtemp(tmpl: cstring): cstring {.importc, header: "stdlib.h".}

proc createUnixSocketDir*(): tuple[path: string, cleanup: proc()] =
  var dirPath = "/tmp/metac_unix_XXXXXXXX"
  if mkdtemp(dirPath) == nil:
    raiseOSError(osLastError())

  proc finish() =
    removeFile(dirPath & "/socket")
    removeDir(dirPath)

  return (dirPath, finish)

proc waitForFile*(path: string) {.async.} =
  var buf: Stat
  while stat(path.cstring, buf) != 0:
    await asyncSleep(10)
