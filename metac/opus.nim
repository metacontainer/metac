import collections

var OPUS_APPLICATION_AUDIO {.importc, header: "<opus/opus.h>".}: cint

type OpusEncoderVal = object
type OpusDecoderVal = object

type OpusEncoder* = ptr OpusEncoderVal
type OpusDecoder* = ptr OpusDecoderVal

{.passl: "-lopus".}

proc opus_encode (st: ptr OpusEncoderVal, pcm: ptr uint16, frame_size: cint, data: pointer, max_data_bytes: int32): int32 {.importc, header: "<opus/opus.h>".}
proc opus_encoder_create (fs: int32, channels: cint, application: cint, error: ptr cint): ptr OpusEncoderVal {.importc, header: "<opus/opus.h>".}
proc opus_encoder_ctl (st: ptr OpusEncoderVal, request: int): cint {.importc, varargs, header: "<opus/opus.h>".}

proc opus_decoder_create (fs: int32, channels: cint, error: ptr cint): ptr OpusDecoderVal {.importc, header: "<opus/opus.h>".}
proc opus_decode (st: ptr OpusDecoderVal, data: pointer, len: int32, pcm: ptr int16, frame_size: cint, decode_fec: cint): cint {.importc, header: "<opus/opus.h>".}

# FIXME: destroy the decoder/encoder object with destructor!

const channels = 2

proc newOpusDecoder*(): OpusDecoder =
  var err: cint
  result = opus_decoder_create(48000, channels, addr err)
  if err != 0: raise newException(Exception, "cannot create opus decoder")

proc decode*(self: OpusDecoder, encoded: Buffer): Buffer =
  const maxSamples = 24000
  let buf = newBuffer(maxSamples * 2 * channels)
  let samples = opus_decode(self, addr encoded[0], encoded.len.int32,
                            cast[ptr int16](addr buf[0]), maxSamples, 0)
  if samples < 0:
    raise newException(Exception, "opus_decode failed")

  return buf.slice(0, samples * 2 * channels)

proc newOpusEncoder*(): OpusEncoder =
  var err: cint
  result = opus_encoder_create(48000, channels, OPUS_APPLICATION_AUDIO, addr err)
  if err != 0: raise newException(Exception, "cannot create opus decoder")

proc encode*(self: OpusEncoder, samples: Buffer): Buffer =
  doAssert samples.len mod (2 * channels) == 0
  var outBuffer = newBuffer(samples.len + 100)

  var encodedSize: int32 = opus_encode(
    self,
    cast[ptr uint16](addr samples[0]), cint(samples.len div (2 * channels)),
    addr outBuffer[0], outBuffer.len.int32)

  if encodedSize < 0:
    raise newException(Exception, "opus_encode failed")

  return outBuffer
