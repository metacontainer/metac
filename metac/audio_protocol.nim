import reactor, metac/audio_sdl, sctp, collections, metac/opus

type
  AudioSinkConcept* = concept x
    getQueuedSize(x) is int
    clearQueuedAudio(x)
    pauseAudioDevice(x, bool)
    queueAudio(x, Buffer)

const samplesPerMs = 48000 div 1000
const channels = 2
const samplesPerPacket = 960

proc record*(conn: SctpConn, source: ByteInput, latency: int) {.async.} =
  let opusEncoder = newOpusEncoder()
  var sampleOffset: int64 = 0
  while true:
    # TODO: handle suspends?
    let data = await source.read(channels * 2 * samplesPerPacket)

    var packet = SctpPacket()
    packet.reliabilityPolicy.reliability = sctpTimedReliability
    packet.reliabilityPolicy.deadline = currentTime() + latency

    if conn.sctpPackets.output.freeBufferSize == 0:
      # probably won't happen often even on too slow connections, due to reliabilityPolicy
      stderr.writeLine "audio: connection too slow, dropping data"
      continue

    packet.data = "\0" & pack(sampleOffset) & opusEncoder.encode(data)
    sampleOffset += samplesPerPacket
    await conn.sctpPackets.output.send(packet)

proc play*(conn: SctpConn, dev: AudioSinkConcept, latency: int) {.async.} =
  doAssert latency <= 1500

  const bytePerSample = 2 * channels
  let latencySamples = latency * samplesPerMs
  var currentSampleOffset: int64 = 0
  var paused = true
  var suspended = false # if true, we won't print "too slow" message for the first packet
  let opusDecoder = newOpusDecoder()

  #block handleHandshake:
  #  let handshakePacket = await conn.sctpPackets.input.receive
  #  if handshakePacket.data[0] != 1:
  #    raise newException(Exception, "first packet received is not a handshake packet")

  proc checkBufferPre() =
    if not paused:
      let qsize = int(dev.getQueuedSize div bytePerSample)
      if qsize == 0:
        if not suspended:
          stderr.writeLine "audio: sender is too slow for us (or dropped data), resetting queue"

        dev.pauseAudioDevice(true)
        paused = true
      elif qsize > latencySamples * 2:
        stderr.writeLine "audio: sender is too fast for us (clock skew?), resetting queue"
        dev.clearQueuedAudio
        dev.pauseAudioDevice(true)
        paused = true

  proc checkBufferPost() =
    if paused:
      if dev.getQueuedSize >= latencySamples:
        stderr.writeLine "audio: resuming"
        dev.pauseAudioDevice(false)
        paused = true

  proc playData(buf: Buffer) =
    checkBufferPre()
    dev.queueAudio(buf)
    checkBufferPost()

  proc playSilence(samples: int64) =
    if samples <= latencySamples:
      playData(newBuffer(int(samples * bytePerSample)))

  asyncFor packet in conn.sctpPackets.input:
    if packet.data.len == 0: continue

    let kind = packet.data[0]
    if kind == 0: # data packet
      if packet.data.len < 10: continue

      let sampleOffset = packet.data.slice(1, 8).unpack(int64)
      if sampleOffset > currentSampleOffset:
        stderr.writeLine "audio: missing samples ($1)" % $(sampleOffset - currentSampleOffset)
        playSilence(sampleOffset - currentSampleOffset)
      let body = opusDecoder.decode(packet.data.slice(9))

      currentSampleOffset += body.len div bytePerSample

      playData(body)
      suspended = false
    elif kind == 1: # suspend
      suspended = true
