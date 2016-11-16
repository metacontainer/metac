from metac.metac import Instance, load
from metac import stream

vm = load('metac/vm.capnp')

instance = Instance('10.234.0.1')
serv = instance.node_admin.getServiceAdmin('vm').service.cast_as(vm.VMServiceAdmin)
launcher = serv.getLauncher().launcher

config = vm.LaunchConfiguration.new_message(
    memory=512,
    vcpu=1,
    machineInfo=vm.MachineInfo.new_message(type=vm.MachineInfo.Type.host),
    serialPorts=[
        vm.SerialPort.new_message(
            driver=vm.SerialPort.Driver.virtio,
            stream=stream.debug_print_stream(instance, '[serial] ')
        )
    ]
)

config.boot.disk = 0

vm = launcher.launch(config).wait()
