import xrest, metac/rest_common, metac/media, options

type
  Rect* = object
    x: float
    y: float
    w: float
    h: float

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

restRef DesktopRef:
  # Desktop is a Screen + mouse/keyboard + clipboard sync
  sctpStream("vncStream")
  sub("video", VideoFeedRef)

#### X11 ####

type
  X11Desktop = object
    displayId: string
    xauthorityPath: string
    virtual: bool

basicCollection(X11Desktop, DesktopRef)
# You can create desktop in one of two ways:
# - by {"virtual": true} and then reading displayId and xauthorityPath - this will use Xvncserver
# - by {"virtual": false, "xauthorityPath": "...", "displayId": "..."} - this will use x11vnc on existing display
