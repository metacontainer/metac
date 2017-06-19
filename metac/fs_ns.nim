# included from metac/fs.nim

type
  LocalNamespace = ref object of RootObj
    instance: ServiceInstance

  LocalMount = ref object of RootObj

proc filesystem(ns: LocalNamespace): Future[Filesystem] =
  return now(just(LocalFilesystem(path: "/", instance: ns.instance).asFilesystem))

proc mount(ns: LocalNamespace, path: string, fs: Filesystem): Future[Mount] {.async.} =
  let stream = await fs.v9fsStream
  let (fd, holder) = await ns.instance.unwrapStream(stream)
  echo "mounting..."
  let process = startProcess(@["mount", "-t", "9p", "-o", "trans=fd,rfdno=4,wfdno=4,uname=root,aname=/,access=client", "none", "/" & path],
                             additionalFiles= @[(4.cint, fd.cint), (2.cint, 2.cint)])
  return holder.castAs(Mount)

proc listMounts(ns: LocalNamespace): Future[seq[Mount]] {.async.} =
  return newSeq[Mount]()

capServerImpl(LocalNamespace, FilesystemNamespace)
