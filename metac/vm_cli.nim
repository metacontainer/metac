import metac/cli_utils, reactor, metac/vm, metac/service_common, xrest, collections

command("metac vm ls", proc()):
  let service = await getServiceRestRef("vm", VMCollection)
  let s = await service.get
  for r in s: echo r
