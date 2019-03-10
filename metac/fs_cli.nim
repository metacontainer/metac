import reactor, collections, metac/fs, metac/cli_utils, metac/fs_impl, metac/service_common, os, sctp

command("metac fs mount", proc(srcRPath: string, dstPath: string, noDaemon=false, mountCollectionRPath="")):
  var dstPath = absolutePath(dstPath)

  if noDaemon and mountCollectionRPath != "":
    raise newException(Exception, "can specify mount collection only in daemon mode")

  let fs = await getRefForPath(expandResourcePath(srcRPath), FilesystemRef)

  if noDaemon:
    await doMount(fs, dstPath)
  else:
    let mountCollection = await getRefForPath(
      if mountCollectionRPath == "": "/fs/mounts" else: mountCollectionRPath,
      MountCollection)
    let r = await mountCollection.create(Mount(
      path: dstPath,
      fs: some(fs)
    ))
    echo r

command("metac fs cat", proc(rpath: string)):
  let f = await getRefForPath(expandResourcePath(rpath), FileRef)
  let conn = await f.data
  let stdout = createOutputFromFd(1)

  await pipe(conn, stdout)
  conn.sctpPackets.input.recvClose
