import metac/service_common, metac/cli_utils, reactor, collections, metac/sctpstream, json, xrest, strformat

type
  WebProxyConfig* = object
    port: int
    token: string

proc defaultConfigPath(): string = getMetacConfigDir() / "webproxy.json"

const webuiPath {.strdefine.} = ""

proc getCookieToken(req: HttpRequest): string =
  let cookies = req.headers.getOrDefault("cookie")
  for part in cookies.split(";"):
    let s = part.split("=")
    if s.len == 2 and s[0].strip == "metactoken":
      return s[1].strip

  return ""

proc returnFile(debugFn: string, releaseFn: string): HttpResponse =
  let fn = getAppDir() / (if webuiPath == "": "../webui/" & debugFn else: webuiPath & releaseFn)
  let ext = fn.split('.')[^1]
  let contentType = case ext
                    of "html": "text/html"
                    of "js": "application/javascript"
                    of "css": "text/css"
                    else: "text/plain"

  return newHttpResponse(
    readFile(fn),
    headers=headerTable({
      "content-type": contentType
    })
  )

proc proxyRequest(req: HttpRequest): Future[HttpResponse] {.async.} =
  let sess = getRootRestRef().sess
  let newReq = withPathSegmentSkipped(req)
  newReq.headers = headerTable([])
  for k in ["content-type"]:
    if k in req.headers: newReq.headers[k] = req.headers[k]

  let conn = await sess.makeConnection(newReq)
  # TODO: handle SCTP
  let resp = await conn.request(sess.createRequest(newReq))
  resp.headers["x-frame-options"] = "deny"
  resp.headers["content-security-policy"] = "default-src 'none'"
  return resp

proc webproxyHandler(config: WebProxyConfig, req: HttpRequest): Future[HttpResponse] {.async.} =

  if req.path == "/static/react.js":
    return returnFile("node_modules/react/umd/react.development.js", "react.min.js")

  if req.path == "/static/react-dom.js":
    return returnFile("node_modules/react-dom/umd/react-dom.development.js", "react-dom.min.js")

  if req.path == "/static/index.js":
    return returnFile("dist/index.js", "index.js")

  if req.path == "/static/index.js.map":
    return returnFile("dist/index.js.map", "index.js.map")

  if req.path.startswith("/?"):
    var setToken = req.getQueryParam("token")
    if setToken != "":
      setToken = encodeHex(decodeHex(setToken)) # ensure token is hex
      return newHttpResponse(
        data="",
        statusCode=303,
        headers=headerTable({
          "location": req.path.split('/')[0] & "?",
          "set-cookie": fmt"metactoken={setToken}; MaxAge=Thu, 01 Jan 2099 00:00:00; HTTPOnly; SameSite=lax",
        })
      )

  if getCookieToken(req) != config.token:
    return newHttpResponse(
      static(staticRead("webui/invalid-token.html")),
      statusCode=403)

  if req.path.startswith("/api/"):
    if req.httpMethod != "GET":
      if req.headers.getOrDefault("origin") != (fmt"localhost:{config.port}"):
        return newHttpResponse("<h1>Invalid origin", statusCode=403)

    return proxyRequest(req)

  return newHttpResponse(static(staticRead("webui/index.html")))

proc main*(configPath="") {.async.} =
  var configPath = configPath
  if configPath == "":
    configPath = defaultConfigPath()

  # TODO: port should be chosen when user runs 'metac webui' (to prevent collisions)
  if not existsFile(configPath):
    writeFile(configPath, $toJson(WebProxyConfig(port: 8777, token: hexUrandom())))

  let config = parseJson(readFile(configPath)).fromJson(WebProxyConfig)

  await runHttpServer(
    addresses=localhostAddresses,
    port=config.port,
    callback=proc(r: auto): auto = webproxyHandler(config, r))

command("metac webui", proc()):
  if not existsFile(defaultConfigPath()):
    stderr.writeLine "webproxy.json doesn't exist. Make sure to start MetaContainer:"
    stderr.writeLine "$ metac start"
    quit(1)

  let config = parseJson(readFile(defaultConfigPath())).fromJson(WebProxyConfig)
  let url = fmt"http://localhost:{config.port}/?token={config.token}"
  echo fmt"Opening URL {url} in browser..."
  discard execShellCmd(fmt"x-www-browser {quoteShell(url)}")

when isMainModule:
  main().runMain
