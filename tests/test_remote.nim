import metac/remote, xrest, reactor, collections, metac/service_common, metac/sctpstream, sctp

type
  TestObj = object
    x: string

  TestImpl = ref object
    ok: Completer[void]

restRef Test:
  get() -> TestObj
  sctpStream("testConn")

proc get(a: TestImpl): TestObj =
  return TestObj(x: "foo")

proc testConn(a: TestImpl, conn: SctpConn, req: HttpRequest) {.async.} =
  echo "request:", req
  #assert req.query == "?foo=bar"
  echo "connected"
  await conn.sctpPackets.output.send(SctpPacket(data: "hello"))
  let packet = await conn.sctpPackets.input.receive()
  echo "received!"
  assert packet.data == "hello1"
  echo "all ok!"

  a.ok.complete()

proc main() {.async.} =
  let impl = TestImpl()
  let handler = restHandler(Test, impl)
  runService("test_remote", handler).onErrorQuit

  let exportedCollection = await getServiceRestRef("exported", ExportedCollection)
  let exportedRef: ExportedRef = await exportedCollection.create(Exported(
    description: "__test__",
    localUrl: "/test_remote/",
  ))
  let exportedVal = await exportedRef.get
  let secretId = exportedVal.secretId
  let remoteRef = await getRefForPath("/remote/" & secretId & "/", Test)

  let v = await remoteRef.get
  assert v.x == "foo"

  impl.ok = newCompleter[void]()

  let conn = await remoteRef.testConn(queryString="foo=bar")
  let packet = await conn.sctpPackets.input.receive()
  assert packet.data == "hello"
  await conn.sctpPackets.output.send(SctpPacket(data: "hello1"))

  await impl.ok.getFuture
  await exportedRef.delete

when isMainModule:
  main().runMain
