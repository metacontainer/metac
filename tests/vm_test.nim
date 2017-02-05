import metac, metac/schemas, metac/vm, metac/stream, collections

proc stdoutOutput(tag: string): ByteOutput =
  proc fun(input: ByteInput) {.async.} =
    asyncFor item in input.lines:
      echo "[" & tag & "] " & item
  return asyncPipe(fun)

proc main() {.async.} =
  let instance = await newInstance("fdca:ddf9:5703::1")
  let serv = instance.thisNodeAdmin.getServiceAdmin("vm").await.toAnyPointer.castAs(VMServiceAdmin)
  let launcher = await serv.getLauncher

  let config = LaunchConfiguration(
    memory: 512,
    vcpu: 1,
    machineInfo: MachineInfo(`type`: MachineInfo_Type.host),
    serialPorts: @[
        SerialPort(
            driver: SerialPort_Driver.virtio,
            stream: instance.wrapStream(BytePipe(
              input: newConstStream(""),
              output: stdoutOutput("serial")))
            )
        ],
    boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.disk,
                                   disk: 0)
  )

  echo config.pprint
  let vm = await launcher.launch(config)

when isMainModule:
  main().runMain
