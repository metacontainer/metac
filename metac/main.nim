## Implements the multicall binary (all programs in one binary).
import os, strutils, reactor
import metac/vm, metac/fs
import tests/vm_test

let name = paramStr(1)

case name:
  of "vm":
    vm.main().runMain()
  of "fs":
    fs.main().runMain()
  # tests
  of "vm-test":
    vm_test.main().runMain()
  else:
    stderr.writeLine("invalid command")
    quit(1)
