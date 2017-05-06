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

  let badConfig = LaunchConfiguration(
    memory: 512,
    vcpu: 1,
    machineInfo: MachineInfo(`type`: MachineInfo_Type.host),
    serialPorts: @[
        SerialPort(
          driver: SerialPort_Driver.default
        )
    ],
    boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.kernel,
                                   kernel: LaunchConfiguration_KernelBoot(
                                     kernel: kernel,
                                     initrd: schemas.File.createFromCap(nullCap),
                                     cmdline: "console=ttyS0 root=/dev/sda")),
    #boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.disk),
    drives: @[
      Drive(device: instance.localBlockDevice(getCurrentDir() / "openwrt-15.05.1-x86-kvm_guest-rootfs-ext4.img"))
    ]
  )

  let config = LaunchConfiguration(
    memory: 512,
    vcpu: 1,
    machineInfo: MachineInfo(`type`: MachineInfo_Type.host),
    serialPorts: @[
        SerialPort(
          driver: SerialPort_Driver.default,
          name: "none"
        )
    ],
    boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.kernel,
                                   kernel: LaunchConfiguration_KernelBoot(
                                     kernel: kernel,
                                     initrd: schemas.File.createFromCap(nullCap),
                                     cmdline: "console=ttyS0 root=/dev/sda")),
    drives: @[]
  )

  echo config.pprint
  let vm = await launcher.launch(config)

  let ports = await vm.serialPorts
  echo "ports: ", ports.pprint
  let (port, portHolder) = await instance.unwrapStreamAsPipe(ports[0])

  asyncFor item in port.input.lines:
     echo "[console] " & item.strip(leading=false)

  echo portHolder.pprint

when isMainModule:
  main().runMain
