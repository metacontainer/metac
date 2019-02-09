import xrest, metac/rest_common, metac/net, strutils

type
  Exported* = object
    secretId*: string
    localUrl*: string
    description*: string

restRef ExportedRef:
  get() -> Exported
  delete()

restRef ExportedCollection:
  create(Exported) -> ExportedRef

  get() -> seq[ExportedRef]

  collection(ExportedRef)

  # Resolve the URL given as argument to a local URL (if possible).
  # Otherwise return empty string.
  call("resolve", string) -> string
