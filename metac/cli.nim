import metac/cli_utils

import metac/daemon

import metac/common_cli
import metac/desktop_cli
import metac/remote_cli
import metac/vm_cli

when isMainModule:
  cli_utils.main("metac")
