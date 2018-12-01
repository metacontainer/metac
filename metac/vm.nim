import xrest, metac/fs, metac/rest_common, collections

type
  DriveDriver* {.pure.} = enum
    virtio, ide

  Drive* = object
    driver*: DriveDriver
    device*: fs.FileRef

  BootKernel* = object
    kernel*: fs.FileRef
    initrd*: fs.FileRef
    cmdline*: string

  SerialPortDriver* {.pure.} = enum
    default, virtio

  SerialPort* = object
    driver*: SerialPortDriver
    name*: string

  VM* = object
    name*: string
    memory*: int # in MiB
    vcpu*: int

    bootDisk*: Option[int]
    bootKernel*: Option[BootKernel]
    drives*: seq[Drive]

    serialPorts*: seq[SerialPort]

restRef VMRef:
  get() -> VM
  update(VM)
  delete()
