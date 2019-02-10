# Small module for interacting with PulseAudio.
import osproc, collections, metac/os_fs, os, reactor, collections

proc listSinkInputs*(): seq[int] =
  let data = execProcess("pacmd", args=["list-sink-inputs"], options={poUsePath})

  for line in data.split("\n"):
    if line.startswith("\tindex: "):
      result.add parseInt(line.split(" ")[1])

proc setDefaultSink*(name: string) =
  discard execProcess("pacmd", args=["set-default-sink", name], options={poUsePath})
  for ident in listSinkInputs():
      discard execProcess("pacmd", args=["move-sink-input", $ident, name], options={poUsePath})

proc createPipeSink*(name: string, description: string): Future[tuple[path: string, cleanup: proc()]] {.async.} =
  let dir = makeTempDir()
  let path = dir / "sink.pipe"

  let output = await checkOutput(@["pactl", "load-module", "module-pipe-sink", "sink_name=" & name, "sink_properties=device.description=" & description, "file=" & path, "channels=2", "rate=48000"])
  echo "pactl --> ", output, "."
  let sinkId = parseInt(output.strip)

  await waitForFile(path)

  proc cleanup() =
    discard execProcess("pactl", args=["unload-module", $sinkId])
    removeFile(path)
    removeDir(dir)

  return (path, cleanup)
