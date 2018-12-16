import xrest, metac/rest_common, metac/net, strutils

type
  Exported* = object
    id*: string
    localUrl*: string
    description*: string

restRef ExportedRef:
  get() -> Exported
  delete()

basicCollection(Exported, ExportedRef)

restRef RemoteService:
  sub("exported", ExportedCollection)
  rawRequest("remote")
