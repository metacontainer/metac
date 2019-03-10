import reactor, collections, metac/fs, metac/service_common, metac/rest_common, metac/remote, nre, xrest, metac/fs_impl, metac/os_fs

proc getLocalPath*(fs: FilesystemRef): Future[Option[string]] {.async.} =
  var uri = RestRef(fs).path
  echo "getLocalPath ", uri
  if not uri.startsWith("/fs/fs/"):
    let exported = await getRefForPath("/exported/", ExportedCollection)
    let resolved = await exported.resolve(uri)
    if resolved != "": uri = resolved

  let parts = uri.split("/")
  if parts.len == 5 and parts[0..2] == @["", "fs", "fs"] and parts[4] == "":
    let path = urlDecode(parts[3])
    return some(path)

  # otherwise, this is likely remote filesystem
  return none(string)

proc getLocalPathOrMount*(fs: FilesystemRef): Future[tuple[path: string, cleanup: proc()]] {.async.} =
  let localPath = await getLocalPath(fs)
  if localPath.isSome:
    var res: tuple[path: string, cleanup: proc ()]
    res.path = localPath.get
    res.cleanup = (proc() = discard)
    return res

  let tmpdir = makeTempDir()
  let mntdir = tmpdir / "mnt"
  createDir(mntdir)

  await doMount(fs, mntdir)

  proc cleanup() =
    doUmount(mntdir).then(proc() =
                            removeDir(mntdir)
                            removeDir(tmpdir)).ignore

  return (mntdir, cleanup)
