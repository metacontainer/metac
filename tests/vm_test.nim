import metac, metac/schemas, metac/vm, metac/fs, metac/stream, collections, os

proc stdoutOutput(tag: string): ByteOutput =
  proc fun(input: ByteInput) {.async.} =
    asyncFor item in input.lines:
      echo "[" & tag & "] " & item.strip
  return asyncPipe(fun)

proc main*() {.async.} =
  let instance = await newInstance("fdca:ddf9:5703::1")
  let serv = instance.thisNodeAdmin.getServiceAdmin("vm").await.toAnyPointer.castAs(VMServiceAdmin)
  let launcher = await serv.getLauncher

  let kernel = fs.localFile(instance, getCurrentDir() / "vmlinuz")

  let config = LaunchConfiguration(
    memory: 512,
    vcpu: 1,
    machineInfo: MachineInfo(`type`: MachineInfo_Type.host),
    serialPorts: @[
        SerialPort(
            driver: SerialPort_Driver.default,
            stream: instance.wrapStream(BytePipe(
              input: newConstInput(""),
              output: stdoutOutput("serial")))
            )
        ],
    boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.kernel,
                                   kernel: LaunchConfiguration_KernelBoot(
                                     kernel: kernel,
                                     initrd: kernel,
                                     cmdline: "console=ttyS0"))
  )

  echo config.pprint
  let vm = await launcher.launch(config)

  await asyncSleep(1000000)

when isMainModule:
  main().runMain
