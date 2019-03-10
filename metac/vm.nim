import xrest, metac/fs, metac/rest_common, collections, metac/net, metac/desktop, options, metac/media

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

  VMFilesystemDriver* = enum
    virtio9p

  VmFilesystem* = object
    driver*: VMFilesystemDriver
    name*: string
    fs*: FilesystemRef

  VmState* {.pure.} = enum
    running, turnedOff

  VM* = object
    meta*: Metadata
    state*: VmState
    memory*: int # in MiB
    vcpu*: int

    bootDisk*: Option[int]
    bootKernel*: Option[BootKernel]
    drives*: seq[Drive]
    filesystems*: seq[VmFilesystem]

    serialPorts*: seq[SerialPort]

restRef VMRef:
  get() -> VM
  sub("desktop", DesktopRef)
  update(VM)
  delete()
  # todo: support patch(VMPatch)

basicCollection(VM, VMRef)
