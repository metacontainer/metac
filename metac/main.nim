## Implements the multicall binary (all programs in one binary).
import os, strutils, reactor, collections
import metac/cli_common
import metac/vm, metac/fs, metac/persistence_service, metac/computevm_service, metac/network_service, metac/sound_service, metac/bridge
import metac/fs_cli, metac/stream_cli, metac/network_cli, metac/sound_cli, metac/persistence_cli, metac/compute_cli
import tests/vm_test, tests/compute_test

dispatchSubcommand({
  "file": (() => fs_cli.mainFile()),
  "fs": (() => fs_cli.mainFs()),
  "net": (() => network_cli.main()),
  "stream": (() => stream_cli.main()),
  "network": (() => network_cli.main()),
  "sound": (() => sound_cli.main()),
  "ref": (() => persistence_cli.main()),
  "run": (() => compute_cli.mainRun()),

  "bridge": (() => bridge.main().runMain()),

  "vm-service": (() => vm.main().runMain),
  "fs-service": (() => fs.main().runMain),
  "computevm-service": (() => computevm_service.main().runMain),
  "persistence-service": (() => persistence_service.main().runMain),
  "network-service": (() => network_service.main().runMain),
  "sound-service": (() => sound_service.main().runMain),

  "vm-test": (() => vm_test.main().runMain()),
  "compute-test": (() => compute_test.main().runMain()),
})
