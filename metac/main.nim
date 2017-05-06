## Implements the multicall binary (all programs in one binary).
import os, strutils, reactor, collections
import metac/cli_common
import metac/vm, metac/fs, metac/persistence_service
import metac/fs_cli
import tests/vm_test

dispatchSubcommand({
  "fs": (() => fs_cli.main()),

  "vm-service": (() => vm.main().runMain),
  "fs-service": (() => fs.main().runMain),
  "persistence-service": (() => persistence_service.main().runMain),

  "vm-test": (() => vm_test.main().runMain()),
})
