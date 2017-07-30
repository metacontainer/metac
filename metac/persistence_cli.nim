import metac/cli_common

proc listCmd() =
  nil

dispatchGen(listCmd)

proc main*() =
  dispatchSubcommand({
    "ls": () => quit(dispatchListCmd(argv, doc="Returns list of saved references.")),
  })
