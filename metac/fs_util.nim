import strutils, posix, os, reactor/syscall, reactor/async, reactor/threading

proc safeJoin(base: string, child: string): string =
  # Safely join `base` and `child` paths - it guarantees that the resulting
  # path will be inside `base`.
  # Here we asume that the filesystem is sane (e.g. probably not Mac OSX)
  if child.split('/').len + base.split('/').len > 40:
    raise newException(ValueError, "path too long")

  var base = base

  for item in child.split('/'):
    if item == ".." or item == "." or item == "-":
      raise newException(ValueError, "invalid path component " & item)
    base &= "/" & item

  return base

const
  O_DIRECTORY = 65536
  O_NOFOLLOW = 131072

proc openat(dirfd: cint, pathname: cstring, flags: cint): cint {.importc, header: "<fcntl.h>".}

proc openAtSync(path: string, finalFlags: cint=O_DIRECTORY): cint =
  var fd: cint = retrySyscall(open("/", O_DIRECTORY or O_NOFOLLOW))
  defer: discard close(fd)

  var parts = path.split('/')
  for i in 0..<parts.len:
    var flags = if i == parts.len - 1: finalFlags else: O_DIRECTORY
    flags = flags or O_NOFOLLOW
    let newFd = retrySyscall(openat(fd, parts[i], flags))
    discard close(fd)
    fd = newFd

  result = fd
  fd = -1

proc openAt*(path: string, finalFlags: cint=O_DIRECTORY): Future[cint] =
  # Open file at `path` without following symlinks.
  return spawn(openAtSync(path, finalFlags))
