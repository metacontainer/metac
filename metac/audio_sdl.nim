import os, sdl2, sdl2/audio, collections

{.passl: "-lSDL2".}

type
  AudioDeviceInfo* = object
    isSource*: bool
    name*: string

export AudioDeviceID

proc pauseAudioDevice*(dev: AudioDeviceID, pause: bool) =
  pauseAudioDevice(dev, if pause: 1 else: 0)

proc clearQueuedAudio*(dev: AudioDeviceID): void {.importc: "SDL_ClearQueuedAudio",
                                                   cdecl, dynlib: sdl2.LibName.}

proc init() =
  var initDone {.global.} = false

  if initDone: return
  initDone = true

  var driver = getenv("METAC_AUDIODRIVER")
  if driver == "":
    driver = "alsa"
  putenv("SDL_AUDIODRIVER", driver)

  if sdl2.init(sdl2.INIT_AUDIO) != SdlSuccess:
    raise newException(Exception, "failed to init SDL audio (check METAC_AUDIODRIVER?)")

proc listDevices*(): seq[AudioDeviceInfo] =
  init()
  for isSource in [0, 1]:
    let n = getNumAudioDevices(cint(isSource))
    for id in 0..<n:
      let name = getAudioDeviceName(cint(isSource), cint(id))
      result.add AudioDeviceInfo(isSource: isSource == 1, name: $name)

proc openDevice*(info: AudioDeviceInfo): AudioDeviceID =
  var desired = AudioSpec()
  desired.freq = 48000
  desired.format = AUDIO_S16LSB
  desired.channels = 2
  desired.samples = 4096 # size of the audio buffer
  var obtained = AudioSpec()
  let dev: AudioDeviceID = openAudioDevice(info.name,
                                           if info.isSource: 1 else: 0, addr desired, addr obtained,
                                           allowed_changes=0)
  if dev < 2:
    raise newException(Exception, "failed to open SDL audio device ($1)" % [$sdl2.getError()])

  return dev

proc queueAudio*(dev: AudioDeviceID, data: Buffer) =
  if queueAudio(dev, addr data[0], uint32(data.len)) != 0:
    raise newException(Exception, "failed to queue audio ($1)" % [$sdl2.getError()])

proc getQueuedSize*(dev: AudioDeviceID): int =
  return getQueuedAudioSize(dev).int

proc closeDevice*(info: AudioDeviceID) =
  closeAudioDevice(info)
