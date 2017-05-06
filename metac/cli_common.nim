import os, collections, sequtils

var argv*: seq[string] = commandLineParams()

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
