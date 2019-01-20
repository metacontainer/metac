import cligen
import metac/cli_utils

import metac/daemon

import metac/common_cli
import metac/desktop_cli
import metac/remote_cli
import metac/vm_cli
import metac/audio_cli
import metac/fs_cli

import metac/web_proxy

when isMainModule:
  try:
    cli_utils.main("metac")
  except cligen.HelpOnly:
    quit(1)
  except cligen.ParseError:
    stderr.writeLine("Error: " & getCurrentException().msg)
    quit(1)
