## Implements the multicall binary (all programs in one binary).
import os, strutils, reactor, collections
import metac/cli_common
import metac/vm, metac/fs, metac/persistence_service, metac/computevm_service, metac/network_service
import metac/fs_cli, metac/stream_cli, metac/network_cli
import tests/vm_test

dispatchSubcommand({
  "fs": (() => fs_cli.main()),
  "net": (() => network_cli.main()),
  "stream": (() => stream_cli.main()),
  "network": (() => network_cli.main()),

  "vm-service": (() => vm.main().runMain),
  "fs-service": (() => fs.main().runMain),
  "computevm-service": (() => computevm_service.main().runMain),
  "persistence-service": (() => persistence_service.main().runMain),
  "network-service": (() => network_service.main().runMain),

  "vm-test": (() => vm_test.main().runMain()),
})
