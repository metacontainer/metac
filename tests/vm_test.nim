import metac, metac/schemas, metac/vm, metac/fs, metac/stream, metac/persistence, collections, os
import metac/fs_cli

proc stdoutOutput(tag: string): ByteOutput =
  proc fun(input: ByteInput) {.async.} =
    asyncFor item in input.lines:
      echo "[" & tag & "] " & item.strip
  return asyncPipe(fun)

proc main*() {.async.} =
  let instance = await newInstance("fdca:ddf9:5703::1")
  let serv = instance.thisNodeAdmin.getServiceAdmin("vm").await.toAnyPointer.castAs(VMServiceAdmin)
  let launcher = await serv.getLauncher

  let kernel = await fs_cli.fileFromUri(instance, "local:" & (getCurrentDir() / "vmlinuz"), schemas.File)
  let drive = await fs_cli.fileFromUri(instance, "local:" & (getCurrentDir() / "openwrt-15.05.1-x86-kvm_guest-rootfs-ext4.img"), schemas.File)

  let config = LaunchConfiguration(
    memory: 512,
    vcpu: 1,
    machineInfo: MachineInfo(`type`: MachineInfo_Type.host),
    serialPorts: @[
        SerialPort(
          driver: SerialPort_Driver.default,
          nowait: true
        )
    ],
    boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.kernel,
                                   kernel: LaunchConfiguration_KernelBoot(
                                     kernel: kernel,
                                     initrd: nullCap,
                                     cmdline: "console=ttyS0 root=/dev/sda")),
    #boot: LaunchConfiguration_Boot(kind: LaunchConfiguration_BootKind.disk),
    networks: @[
      Network(driver: Network_Driver.virtio, network: nullCap)
    ],
    drives: @[
      Drive(device: drive)
    ]
  )

  echo config.pprint
  let vm = await launcher.launch(config)

  let port = await vm.serialPort(0)
  let portRef = await port.castAs(Persistable).createSturdyRef(nullCap, false)
  echo portRef.formatSturdyRef

when isMainModule:
  main().runMain
