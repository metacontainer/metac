import metac/cli_utils, reactor, metac/remote, metac/service_common, xrest, collections

command("metac exported ls", proc()):
  let service = await getServiceRestRef("exported", ExportedCollection)
  let refs = await service.get
  for r in refs:
    echo r

command("metac export", proc(path: string, description="")):
  let service = await getServiceRestRef("exported", ExportedCollection)
  let resp = await service.create(Exported(
    localUrl: path,
    description: description
  ))
  echo resp
