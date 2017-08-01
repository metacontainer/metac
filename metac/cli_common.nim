import os, collections, sequtils, reactor, cligen

var argv*: seq[string] = commandLineParams()

template defineExporter*(name, makeuri) =
  proc name(uri: string, persistent=false) =
    if uri == nil:
      quit("missing required parameter")

    asyncMain:
      let instance = await newInstance()
      let file = await makeuri(instance, uri)
      let sref = await file.castAs(schemas.Persistable).createSturdyRef(nullCap, persistent)
      echo sref.formatSturdyRef

  dispatchGen(name)

proc dispatchSubcommand*[T](handlers: openarray[(string, T)]) =
  # use T instead of proc() to workaround {.locks: <unknown>.}
  let arg = if argv.len == 0: "" else: argv[0]
  if argv.len != 0: argv.delete 0

  var expected: seq[string] = @[]
  for info in handlers:
    if info[0] == arg:
      info[1]()
      return

    expected.add info[0]

  stderr.writeLine("Invalid subcommand '$1'. Expected one of: $2." % [arg, expected.join(", ")])
  quit(1)

proc renderTable*(table: seq[seq[string]]) =
  if table.len == 0: return

  var colSize = newSeq[int](table[0].len)

  for row in table:
    for i, s in row:
      colSize[i] = max(colSize[i], s.strip.len)

  for row in table:
    var line = ""
    for i, s in row:
      line &= s.strip
      if i + 1 != row.len:
         line &= repeat(' ', colSize[i] + 1 - s.len)
    echo line

import reactor, capnp, metac/instance, metac/schemas, metac/persistence, collections, cligen
export reactor, capnp, instance, schemas, persistence, collections, cligen
