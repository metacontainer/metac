import xrest, metac/rest_common, metac/media, options

type AudioSink* = object
  name*: string

type AudioSource* = object
  name*: string

restRef AudioSinkRef:
  get() -> AudioSink
  sctpStream("audioStream")

restRef AudioSourceRef:
  get() -> AudioSource
  sctpStream("audioStream")

immutableCollection(AudioSink, AudioSinkRef)
immutableCollection(AudioSource, AudioSourceRef)

restRef AudioService:
  sub("sinks", AudioSinkCollection)
  sub("sources", AudioSourceCollection)
