## Client for the Simple PTY Protocol.
import reactor, tables, posix, collections, reactor/file, reactor/process, termios, os

proc saveMode(fd: cint): Termios =
  if tcgetattr(fd, addr result) != 0:
    raiseOSError(osLastError())

proc setRaw(fd: FileHandle, time: cint = TCSAFLUSH) =
  # from stdlib terminal.nim
  var mode: Termios
  if fd.tcgetattr(addr mode) != 0:
    raiseOSError(osLastError())
  mode.c_iflag = mode.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or
                                            ISTRIP or IXON)
  mode.c_oflag = mode.c_oflag and not Cflag(OPOST)
  mode.c_cflag = (mode.c_cflag and not Cflag(CSIZE or PARENB)) or CS8
  mode.c_lflag = mode.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
  mode.c_cc[VMIN] = 1.cuchar
  mode.c_cc[VTIME] = 0.cuchar
  if fd.tcsetattr(time, addr mode) != 0:
    raiseOSError(osLastError())

var globalSavedMode: Termios
var modeSaved: bool

proc restoreGlobalMode() {.noconv.} =
  discard tcsetattr(0, TCSADRAIN, addr globalSavedMode)

proc restoreModeAtExit() =
  if not modeSaved:
    globalSavedMode = saveMode(0)
    modeSaved = true
    addQuitProc(restoreGlobalMode)

proc wrapClientTTY*(fd: cint, conn: BytePipe): Future[void] {.async.} =
  ## Start SPTY client.
  let tty = streamFromFd(dup(fd))

  restoreModeAtExit()
  var termMode = saveMode(fd)
  setRaw(fd)

  let lock = newAsyncMutex()

  defer:
    discard tcsetattr(fd, TCSADRAIN, addr termMode)

  proc sendMsg(msg: string) {.async.} =
    await lock.lock
    defer: lock.unlock

    await conn.output.write(pack(msg.len.int32, littleEndian) & msg)

  proc handleSigwinch() =
    var winsize: IOctl_WinSize

    if ioctl(fd, TIOCGWINSZ, addr winsize) != 0:
      stderr.writeLine("TIOCGWINSZ failed")
      return

    let msg = "\1" & pack(winsize.ws_col.int32, littleEndian) & pack(winsize.ws_row.int32, littleEndian)
    sendMsg(msg).ignore
  
  # memory leak, but we don't care
  addSignalHandler(cint(28) #[ SIGWINCH ]#, handleSigwinch)
  handleSigwinch() # send initial size

  proc readTty() {.async.} =
    while true:
      let data = await tty.input.readSome(4096)
      await sendMsg("\0" & data)

  readTty().onErrorClose(conn.output)

  asyncFor chunk in conn.input.readChunksPrefixed(littleEndian):
    if chunk[0] == '\0':
      await tty.output.write(chunk[1..^1])

proc wrapClientTTY*(fd: cint): Future[BytePipe] {.async.} =
  let (conn1, conn2) = newPipe(byte)
  wrapClientTTY(fd, conn1).onErrorClose(conn1.input)
  return conn2

proc openpty(amaster: ptr cint, aslave: ptr cint, name: cstring, termp: pointer, winp: pointer): cint {.importc, header: "<pty.h>".}
var TIOCSWINSZ {.importc, header: "<pty.h>".}: culong

proc createServerTTY*(conn: BytePipe): Future[cint] {.async.} =
  var master, slave: cint
  if openpty(addr master, addr slave, nil, nil, nil) != 0:
    asyncRaise "openpty failed"

  # let slaveDup = dup(slave)
  let ttyFd = dup(master)
  let tty = streamFromFd(master)

  proc handleWrites() {.async.} =
    defer: discard close(ttyFd)

    asyncFor chunk in conn.input.readChunksPrefixed(littleEndian):
      if chunk[0] == '\0': # data
        await tty.output.write chunk[1..^1]
      elif chunk[0] == '\1' and chunk.len >= 9: # terminal size
        let width = unpack(chunk[1..<5], int32, littleEndian).int
        let height = unpack(chunk[5..<9], int32, littleEndian).int

        if width > 1000 or height > 1000 or width < 1 or height < 1:
          stderr.writeLine("simple_pty: invalid size")
          continue

        var winsize = IOctl_WinSize(ws_row: height.uint16, ws_col: width.uint16, ws_xpixel: 100, ws_ypixel: 100)

        if ioctl(ttyFd.FileHandle, TIOCSWINSZ, addr winsize) != 0:
          stderr.writeLine("TIOCSWINSZ failed")

  proc handleReads() {.async.} =
    while true:
      let data = await tty.input.readSome(4096)
      await conn.output.write(pack((data.len + 1).int32, littleEndian) & "\0" & data)

  handleWrites().onErrorClose(conn.input)
  handleReads().onErrorClose(conn.output)

  return slave

proc main() {.async.} =
  let (conn1, conn2) = newPipe(byte)
  let pty = await createServerTTY(conn1)
  # setsid --ctty or see `man login_tty`
  let process = startProcess(@["setsid", "bash"], # "--ctty"
                             additionalFiles = @[(cint(0), pty), (cint(1), pty), (cint(2), pty)])
  wrapClientTTY(0, conn2).ignore
  let code = await process.wait
  quit(code)

when isMainModule:
  main().runMain
