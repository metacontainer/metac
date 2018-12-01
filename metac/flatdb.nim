## Database that stores JSON objects in flat files.
import strutils, json, collections, os

type FlatDB* = ref object
  path: string

const AllowedCharacters = Digits + Letters + {'_', '-', '.'}

proc isKeyValid*(s: string): bool =
  for ch in s:
    if ch notin AllowedCharacters: return false
  return true

proc makeKeyBasedOnName*(s: string): string =
  for ch in s:
    if ch in AllowedCharacters: result &= ch
  result &= "-"
  result &= hexUrandom(10)

proc pathForKey(db: FlatDB, key: string): string =
  if not isKeyValid(key):
    raise newException(Exception, "invalid key")

  return db.path & "/" & key & ".json"

proc `[]`*(db: FlatDB, key: string): JsonNode =
  parseJson(readFile(pathForKey(db, key)))

proc `[]=`*(db: FlatDB, key: string, value: JsonNode) =
  let path = pathForKey(db, key)
  writeFile(path & ".tmp", pretty(value))
  moveFile(path & ".tmp", path)

iterator keys*(db: FlatDB): string =
  for pc in walkDir(db.path, relative=true):
    let name = pc.path
    if not name.endsWith(".json"): continue
    let ident = name[0..^6]
    if isKeyValid(ident):
      yield ident

proc makeFlatDB*(path: string): FlatDB =
  createDir(path)
  return FlatDB(path: path)

when isMainModule:
  import sequtils

  let tempdir = getTempDir() / "flatdb-test"
  removeDir(tempdir)

  let db = makeFlatDB(tempdir)
  doAssert toSeq(db.keys) == @[]

  db["foo"] = %{"bar": %5}
  doAssert toSeq(db.keys) == @["foo"]
  doAssert db["foo"] == %{"bar": %5}
