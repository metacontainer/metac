# Create a pulseaudio device that just plays the sound to another one :)
import reactor, collections, metac/audio_pulse, metac/audio_sdl, sequtils

proc main() {.async.} =
  let (path, cleanup) = await createPipeSink("test", "Test_Sink")

  let fd = await open(path, ReadOnly)
  let pipeInput = createInputFromFd(fd.int.cint)

  let sink = listDevices().filterIt(not it.isSource)[0]
  echo "using sink ", sink
  let dev = openDevice(sink)
  dev.pauseAudioDevice(false)

  while true:
    let data = await pipeInput.readSome(1024)
    dev.queueAudio(data)

when isMainModule:
  main().runMain
