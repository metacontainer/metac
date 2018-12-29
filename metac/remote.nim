import xrest, metac/rest_common, metac/net, strutils

type
  Exported* = object
    secretId*: string
    localUrl*: string
    description*: string

restRef ExportedRef:
  get() -> Exported
  delete()

basicCollection(Exported, ExportedRef)
