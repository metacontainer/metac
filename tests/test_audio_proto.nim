import reactor, sctp, reactor/testpipe, metac/audio_protocol, times, math
import tests/signal_tool

type
  MockAudioSink = ref object
    startTime: float

const samplesPerMs = 48000 div 1000
const bytePerSample = 4

proc getQueuedSize*(x: MockAudioSink): int =
  return 0

proc clearQueuedAudio*(x: MockAudioSink) =
  discard

proc pauseAudioDevice*(x: MockAudioSink, paused: bool) =
  discard

proc queueAudio*(x: MockAudioSink, buf: Buffer) =
  echo "queue ", epochTime() - x.startTime, " ", buf.len
  let realFreq = float(getFreq(buf.slice(0, 2048)) * samplesPerMs * 1000) / 512
  let roundedFreq = int(round(realFreq / 1000)) * 1000
  echo roundedFreq

proc writeSound(output: ByteOutput, data: Buffer) {.async.} =
  var pos = 0
  const packetMs = 10

  var expectedTime = epochTime()

  while pos < data.len:
    var length = min(packetMs * samplesPerMs * bytePerSample, data.len - pos)
    let d = data.slice(pos, length)
    await output.write(d)
    expectedTime += packetMs / 1000'f

    let needSleep = expectedTime - epochTime()
    if needSleep > 0: await asyncSleep(int(needSleep * 1000))

    pos += length

proc main() {.async.} =
  let (pipe1, pipe2, packetsA, packetsB) = newTwoWayTestPipe(mtu=1300)
  let connA = newSctpConn(packetsA)
  let connB = newSctpConn(packetsB)

  let delay = 100
  pipe1.delay = delay
  pipe1.delayJitter = 0
  pipe1.packetLoss = 0
  let maxLatency = delay * 2

  let (sndGeneratorInput, sndGeneratorOutput) = newInputOutputPair[byte](bufferSize = 1024 * 1024)

  record(connA, sndGeneratorInput, maxLatency).ignore

  let mockAudioSink = MockAudioSink(startTime: epochTime())

  play(connB, mockAudioSink, maxLatency).ignore

  await sndGeneratorOutput.writeSound(makeSignal(1000 * samplesPerMs, 5000))

when isMainModule:
  main().runMain
