import os, sys
sys.path.append(os.path.realpath(os.path.dirname(__file__) + '/../../py'))
os.chdir(os.path.dirname(__file__))

from metac.core import Metadata
from metac.vm import Vm, get_vms, VmFilesystem, BootKernel
from metac.fs import get_fs, get_file

res = get_vms().create(Vm(
    meta=Metadata(name='hello'),
    memory=1024,
    bootKernel=BootKernel(
        kernel=get_file('../../helpers/agent-vmlinuz'),
        cmdline='root=/dev/root rootfstype=9p rootflags=trans=virtio init=/bin/sh',
    ),
    filesystems=[
        VmFilesystem("/dev/root", get_fs('./shared/')),
    ],
))
print(res)
