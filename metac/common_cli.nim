import metac/cli_utils, reactor, metac/desktop, xrest, metac/service_common

command("metac rm", proc(url: string)):
  let r = await getRefForPath(url)
  await delete(r)
