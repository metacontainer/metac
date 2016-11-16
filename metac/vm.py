from metac.metac import Instance, load, CastToLocal
from metac import stream
import capnp
import os

metac_capnp = load('metac/metac.capnp')
vm_capnp = load('metac/vm.capnp')
vm_internal_capnp = load('metac/vm_internal.capnp')

instance = None

class VMServiceAdminImpl(vm_capnp.VMServiceAdmin.Server):
    def getLauncher(self, **kwargs):
        return VMLauncherImpl()

def get_machine_type(info):
    s = {
        vm_capnp.MachineInfo.Type.kvm64: 'kvm64',
        vm_capnp.MachineInfo.Type.host: 'host',
    }[info.type]

    if info.hideVm:
        s += ',kvm=off'

    return s

def qemuQuoteName(s):
    s = s.encode('utf8')
    if b';' in s or b':' in s or b',' in s or b'\0' in s:
        raise ValueError('invalid name')
    return s.decode('utf8')

class VM(vm_internal_capnp.VMInternal.Server):
    def __init__(self):
        self._holders = []

    def __del__(self):
        print('delete VM')

    def init(self, config, _context):
        cmdline = ['qemu-system-x86_64',
                   '-enable-kvm',
                   '-nographic',
                   '-nodefaults',
                   '-sandbox', 'on']

        # boot
        if config.boot.which() == 'disk':
            if config.boot.disk != 0:
                raise Exception('can only boot from the first hard disk')
            cmdline += ['-boot', 'c']
        else:
            raise Exception('unsupported boot method')
        
        # memory
        cmdline += ['-m', str(config.memory)]

        # vcpu
        cmdline += ['-vcpu', str(config.vcpu)]

        # machineInfo
        cmdline += ['-M', get_machine_type(config.machineInfo)]

        # networks

        # drives

        # serialPorts
        for i, serialPort in enumerate(config.serialPorts):
            sock, holder = stream.unwrap(serialPort.stream)
            files.append(sock)
            cmdline += [
                '-add-fd', 'fd=%d,set=%d' % (sock.fileno(), sock.fileno()),
                '-chardev', 'serial,id=serial%d,path=/dev/fdset/%d' % (i, sock.fileno())
            ]
            if serialPort.driver == vm_capnp.SerialPort.Driver.virtio:
                cmdline += [
                    '-device', 'virtserialport,chardev=serial%d,name=%s' % (i, qemuQuoteName(serialPort.name))]
            else:
                cmdline += [
                    '-device', 'chardev:serial%d' % i]


        # pciDevices
        print(cmdline)

class VMLauncherImpl(vm_capnp.VMLauncher.Server):
    def launch(self, config, **kwargs):
        print('launch', config)
        obj = instance.threaded_object(VM, vm_internal_capnp.VMInternal)
        return obj.init(config)

class VMServiceImpl(metac_capnp.Service.Server):
    pass

class PciDeviceImpl(vm_capnp.PciDevice.Server, CastToLocal):
    pass

if __name__ == '__main__':
    import sys

    instance = Instance(sys.argv[1])
    holder = instance.node_admin.registerNamedService('vm', VMServiceImpl(), VMServiceAdminImpl())
    instance.wait()
