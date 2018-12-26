import tables, strutils, macros, cligen, os, sequtils
export cligen

type
  CommandProc = (proc(cmdline: seq[string]): int)
  CommandHandler = object
    isMulticommand: bool
    handler: CommandProc

var commands = initTable[seq[string], CommandHandler]()

proc addCommand(name: string, handler: CommandProc) =
  var splitCmd = `name`.split(" ")
  for i in 1..splitCmd.len-1:
    commands[splitCmd[0..<i]] = CommandHandler(isMulticommand: true)

  commands[splitCmd] = CommandHandler(
    isMulticommand: false,
    handler: handler)

macro command*(name: string, args: untyped, body: untyped): untyped =
  result = newNimNode(nnkStmtList)

  let realBody = quote do:
      asyncMain(`body`)

  let funcName = newIdentNode(name.strVal)
  let funcDef = newNimNode(nnkProcDef)
  funcDef.add(funcName, newNimNode(nnkEmpty), newNimNode(nnkEmpty),
              args[0], newNimNode(nnkEmpty), newNimNode(nnkEmpty), realBody)

  result.add(funcDef)

  result.add(quote do:
    dispatchGen(`funcName`, `name`, doc=""))

  let dispatchName = newIdentNode("dispatch" & name.strVal)

  result.add(quote do:
    addCommand(`name`, proc(cmdline: seq[string]): int = `dispatchName`(cmdline)))

proc main*(command: string) =
  let params = @[command] & commandLineParams()
  for i in 1..params.len:
    let subcommand = params[0..<i]
    if subcommand notin commands:
      stderr.writeLine "invalid subcommand: " & subcommand
      quit(1)

    if not commands[subcommand].isMulticommand:
      let code = commands[subcommand].handler(params[i..^1])
      quit(code)

  let alternatives = toSeq(commands.keys).filterIt( it.len == params.len+1 and it[0..<params.len] == params ).mapIt(it[^1])

  stderr.writeLine "usage: " & params.join(" ") & " " & alternatives.join("|")
  quit(1)
