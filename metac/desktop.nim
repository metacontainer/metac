import xrest, metac/rest_common, metac/media, options

type
  Rect* = object
    x*: float
    y*: float
    w*: float
    h*: float

  VideoFeed* = object
    rect: Rect
    video: VideoStreamRef

restRef VideoFeedRef:
  get() -> VideoFeed
  update(VideoFeed)
  delete()

basicCollection(VideoFeed, VideoFeedRef)

restRef ScreenRef:
  # A device that can display video.
  sub("feeds", VideoFeedCollection)

type
  DesktopFormat* {.pure.} = enum
    unknown, vnc, spice

  Desktop* = object
    supportedFormats*: seq[DesktopFormat]

restRef DesktopRef:
  # Desktop is a Screen + mouse/keyboard + (optional) clipboard sync
  sctpStream("desktopStream")
  sub("video", VideoStreamRef)
  get() -> Desktop

#### X11 ####

type
  X11Desktop* = object
    displayId*: Option[string]
    xauthorityPath*: Option[string]
    virtual*: bool
    name*: string

restRef X11DesktopRef:
  sub("desktop", DesktopRef)
  get() -> X11Desktop
  delete()

basicCollection(X11Desktop, X11DesktopRef)
# You can create desktop in one of two ways:
# - by {"virtual": true} and then reading displayId and xauthorityPath - this will use Xvncserver
# - by {"virtual": false, "xauthorityPath": "...", "displayId": "..."} - this will use x11vnc on existing display
