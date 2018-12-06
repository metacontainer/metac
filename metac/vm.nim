import xrest, metac/fs, metac/rest_common, collections, metac/net, metac/desktop

type
  DriveDriver* {.pure.} = enum
    virtio, ide

  Drive* = object
    driver*: DriveDriver
    device*: fs.FileRef

  BootKernel* = object
    kernel*: net.ByteStream
    initrd*: Option[net.ByteStream]
    cmdline*: string

  SerialPortDriver* {.pure.} = enum
    default, virtio

  AfterLaunch*[T] = Option[T]
    # used for parameters that are available only after launch

  SerialPort* = object
    driver*: SerialPortDriver
    name*: string
    nowait*: bool
    stream*: AfterLaunch[ByteStream]

  VmState* {.pure.} = enum
    running, turnedOff

  VM* = object
    state*: VmState
    name*: string
    memory*: int # in MiB
    vcpu*: int

    bootDisk*: Optional[int]
    bootKernel*: Optional[BootKernel]
    drives*: seq[Drive]

    serialPorts*: seq[SerialPort]

    desktop*: AfterLaunch[DesktopRef]

restRef VMRef:
  get() -> VM
  update(VM)
  delete()
  # todo: support patch(VM)

basicCollection(VMRef, VM)
