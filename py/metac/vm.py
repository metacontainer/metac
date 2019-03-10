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
    cmdline: str
    initrd: Optional[Ref] = None

class SerialPortDriver(Enum):
    default = 1
    virtio = 2

class SerialPort(NamedTuple):
    driver: SerialPortDriver
    name: str
    nowait: bool

class VmFilesystemDriver(Enum):
    virtio9p = 1

class VmFilesystem(NamedTuple):
    name: str
    fs: FilesystemRef
    driver: VmFilesystemDriver = VmFilesystemDriver.virtio9p

class VmState(Enum):
    running = 1
    turnedOff = 2

class Vm(NamedTuple):
    meta: Metadata
    memory: int
    state: VmState = VmState.running
    vcpu: int = 1

    bootDisk: Optional[int] = None
    bootKernel: Optional[BootKernel] = None
    drives: List[Drive] = []
    filesystems: List[VmFilesystem] = []

    serialPorts: List[SerialPort] = []

class VmRef(Ref, GetMixin[Vm], DeleteMixin):
    value_type = Vm

class VmCollection(Ref, CollectionMixin[Vm, VmRef]):
    value_type = Vm
    ref_type = VmRef

def get_vms() -> VmCollection:
    return VmCollection('/vm/')

if __name__ == '__main__':
    vms = get_vms().values()
    get_vms().create(Vm(
        meta=Metadata(name='hello'),
        memory=1024,
    ))
    print(vms)
