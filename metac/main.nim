## Implements the multicall binary (all programs in one binary).
import os, strutils, reactor, collections
import metac/cli_common
import metac/bridge, metac/vm, metac/fs, metac/persistence_service, metac/computevm_service, metac/network_service, metac/sound_service, metac/desktop_service
import metac/fs_cli, metac/stream_cli, metac/network_cli, metac/sound_cli, metac/persistence_cli, metac/compute_cli, metac/common_cli, metac/desktop_cli
import tests/vm_test, tests/compute_test

dispatchSubcommand({
  "file": (() => fs_cli.mainFile()),
  "fs": (() => fs_cli.mainFs()),
  "net": (() => network_cli.main()),
  "stream": (() => stream_cli.main()),
  "network": (() => network_cli.main()),
  "sound": (() => sound_cli.main()),
  "obj": (() => persistence_cli.mainObj()),
  "ref": (() => persistence_cli.mainRef()),
  "run": (() => compute_cli.mainRun()),
  "desktop": (() => desktop_cli.main()),

  "destroy": (() => common_cli.mainDestroy()),

  "bridge": (() => bridge.main().runMain()),

  "vm-service": (() => vm.main().runMain),
  "fs-service": (() => fs.main().runMain),
  "computevm-service": (() => computevm_service.main().runMain),
  "persistence-service": (() => persistence_service.main().runMain),
  "network-service": (() => network_service.main().runMain),
  "sound-service": (() => sound_service.main().runMain),
  "desktop-service": (() => desktop_service.main().runMain),

  "sshfs-mount-helper": (() => fs.sshfsMountHelper().runMain),

  "vm-test": (() => vm_test.main().runMain()),
  "compute-test": (() => compute_test.main().runMain()),
})
