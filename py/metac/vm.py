from metac.core import *
from metac.fs import FilesystemRef, FileRef
from typing import NamedTuple, Optional
from enum import Enum

class DriveDriver(Enum):
    virtio = 1
    ide = 2

class Drive(NamedTuple):
    driver: DriveDriver
    device: FileRef

class BootKernel(NamedTuple):
    kernel: Ref
    initrd: Optional[Ref]
    cmdline: str

class SerialPortDriver(Enum):
    default = 1
    virtio = 2

class SerialPort(NamedTuple):
    driver: SerialPortDriver
    name: str
    nowait: bool

class VMFilesystemDriver(Enum):
    virtio9p = 1

class VmFilesystem(NamedTuple):
    driver: VMFilesystemDriver
    name: str
    fs: FilesystemRef

class VmState(Enum):
    running = 1
    turnedOff = 2

class VM(NamedTuple):
    meta: Metadata
    memory: int
    state: VmState = VmState.running
    vcpu: int = 1

    bootDisk: Optional[int] = None
    bootKernel: Optional[BootKernel] = None
    drives: List[Drive] = []
    filesystems: List[VmFilesystem] = []

    serialPorts: List[SerialPort] = []

class VMRef(Ref, GetMixin[VM], DeleteMixin):
    value_type = VM

class VMCollection(Ref, CollectionMixin[VM, VMRef]):
    value_type = VM
    ref_type = VMRef

def get_vms() -> VMCollection:
    return VMCollection('/vm/')

if __name__ == '__main__':
    vms = get_vms().values()
    get_vms().create(VM(
        meta=Metadata(name='hello'),
        memory=1024,
    ))
    print(vms)
