import os, metac/audio, xrest, metac/service_common, metac/audio_sdl, reactor/http, collections, metac/sctpstream, sctp, metac/audio_protocol

type AudioServiceImpl = object

proc `sinks/get`(s: AudioServiceImpl): seq[AudioSinkRef] =
  return listDevices().filterIt(not it.isSource).mapIt(makeRef(AudioSinkRef, urlEncode(it.name)))

proc `sinks/item/get`(s: AudioServiceImpl, name: string): AudioSink =
  return AudioSink(name: name)

proc `sinks/item/audioStream`(s: AudioServiceImpl, name: string, conn: SctpConn, req: HttpRequest) {.async.} =
  let latency = parseInt(req.getQueryParam("latency")) # in ms
  let dev = openDevice(AudioDeviceInfo(name: name, isSource: false))
  defer: closeDevice(dev)

  await audio_protocol.play(conn, dev, latency)

proc `sources/get`(s: AudioServiceImpl): seq[AudioSourceRef] =
  return listDevices().filterIt(it.isSource).mapIt(makeRef(AudioSourceRef, urlEncode(it.name)))

proc `sources/item/get`(s: AudioServiceImpl, name: string): AudioSink =
  return AudioSink(name: name)

proc `sources/item/audioStream`(s: AudioServiceImpl, name: string, conn: SctpConn, req: HttpRequest) {.async.} =
  discard

proc main*() {.async.} =
  let self = AudioServiceImpl()

  let handler = restHandler(AudioService, self)
  await runService("audio", handler)
