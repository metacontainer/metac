import metac/cli_utils, reactor, metac/desktop, xrest, metac/service_common, json

command("metac rm", proc(url: string)):
  let r = await getRefForPath(url)
  await delete(r)

command("metac inspect", proc(url: string)):
  let r = await getRefForPath(url)
  let resp = await get(r, JsonNode)
  echo resp.pretty
