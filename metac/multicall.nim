## Implements the muliticall binary (all programs in one binary).
import os, strutils, reactor
import metac/vm
import tests/vm_test

let name = paramStr(0).split("/")[^1]

if name == "metac-vm":
  vm.main().runMain()
if name == "vm-test":
  vm_test.main().runMain()
else:
  stderr.writeLine("invalid command")
  quit(1)
