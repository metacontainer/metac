import xrest, metac/rest_common, metac/service_common, reactor, collections

restRef Test:
  sctpStream("testConn")

type TestImpl* = ref object

proc testConn(t: TestImpl, s: SctpConn, req: RestRequest) {.async.} =
  echo "connected"
  await s.sctpPackets.output.send(SctpPacket(data: "hello"))
  let packet = await s.sctpPackets.input.receive()
  echo "received!"
  assert packet.data == "hello1"
  echo "all ok!"

  quit(0)

proc main() {.async.} =
  let t = TestImpl()
  let handler = restHandler(Test, t)
  let fut2 = runService("test_sctp", handler)
  fut2.ignore

  let rt = await getServiceRestRef("test_sctp", Test)
  let conn = await rt.testConn()
  let packet = await conn.sctpPackets.input.receive()
  assert packet.data == "hello"
  echo "(1) received!"
  await conn.sctpPackets.output.send(SctpPacket(data: "hello1"))
  await fut2

when isMainModule:
  main().runMain
