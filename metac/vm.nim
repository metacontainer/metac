import xrest, metac/fs, metac/rest_common, collections

type
  DriveDriver* = enum
    virtio, ide

  Drive* = object
    driver*: DriveDriver
    device*: fs.FileRef

  BootKernel* = object
    kernel*: fs.FileRef
    initrd*: fs.FileRef
    cmdline*: string

  VM* = object
    name*: string
    memory*: int # in MiB
    vcpu*: int

    bootDisk*: Option[int]
    bootKernel*: Option[BootKernel]
    drives*: seq[Drive]

restRef VMRef:
  get() -> VM
  update(VM)
  delete()
