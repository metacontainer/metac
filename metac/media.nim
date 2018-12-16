import xrest, metac/rest_common

type
  VideoStremaFormat* {.pure.} = enum
    vnc, spice, mjpeg, h264

  VideoStreamInfo* = object
    supportedFormats*: seq[VideoStremaFormat]

restRef VideoStreamRef:
  get() -> VideoStreamInfo
  sctpStream("videoStream")

type
  SoundStreamInfo* = object
    supportedFormats: seq[string]

restRef SoundStreamRef:
  # e.g. microphone or output from desktop
  get() -> SoundStreamRef
  sctpStream("soundStream")

type
  SoundBinding* = object
    source*: SoundStreamRef

restRef SoundBindingRef:
  update(SoundBinding)
  delete()

basicCollection(SoundBinding, SoundBindingRef)

restRef SoundTargetRef:
  # e.g. a speaker or desktop microphone input

  sub("bindings", SoundBindingCollection)
