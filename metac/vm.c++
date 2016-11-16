#include "metac/metac.h"
#include "metac/vm.capnp.h"
#include "metac/kjfixes.h"
#include "metac/stream.h"
#include "metac/subprocess.h"
#include <capnp/ez-rpc.h>
#include <kj/debug.h>
#include <iostream>

namespace metac {
namespace vm {

class VMImpl : public VM::Server {

};

class PciDeviceImpl : public PciDevice::Server {

};

std::string qemuQuoteName(std::string name) {
    for (char ch : name) {
        // TODO
        KJ_REQUIRE(ch != ';' && ch != ':' && ch != '\n' && ch != ',' && ch != '"' && ch != '\'');
    }
    return name;
}

class VMLauncherImpl : public VMLauncher::Server {
    Rc<Instance> instance;
    std::vector<Holder::Client> holders;
    kj::Own<subprocess::Process> qemuProcess;
    kj::Array<FdAndHolder> serialPortStreams;
public:
    VMLauncherImpl(Rc<Instance> instance): instance(instance) {}

    std::string getMachineType(MachineInfo::Reader info) {
        std::string s;
        switch (info.getType()) {
        case MachineInfo::Type::KVM64: s = "kvm64"; break;
        case MachineInfo::Type::HOST: s = "host"; break;
        default: KJ_REQUIRE(false, "bad machine type");
        }

        if(info.getHideVm())
            s += ",kvm=off";

        return s;
    }

    kj::Promise<void> launch(LaunchContext context) override {
        // This is anything, but elegant. This service should probably be moved to Nim, once
        // capnp.nim RPC is ready.
        auto config = context.getParams().getConfig();
        auto serialPortStreams = KJ_MAP(port, config.getSerialPorts()) {
            return unwrapStreamAsFd(instance, port.getStream());
        };

        return kj::joinPromises(kj::mv(serialPortStreams)).
            then([context{std::move(context)}, this](kj::Array<FdAndHolder> r) mutable {
                this->serialPortStreams = std::move(r);
                return launchNext(std::move(context));
            });
    }

    kj::Promise<void> launchNext(LaunchContext context) {
        auto config = context.getParams().getConfig();
        std::vector<int> keepFds;

        std::vector<std::string> cmdline = {
            "qemu-system-x86_64",
            "-enable-kvm",
            "-nographic",
            "-nodefaults",
            "-sandbox", "on"};

        // boot
        if (config.getBoot().isDisk()) {
            KJ_REQUIRE(config.getBoot().getDisk() == 0, "can only boot from the first hard disk");
            cmdline += {"-boot", "c"};
        } else {
            KJ_REQUIRE(false, "unsupported boot method");
        }

        // memory
        cmdline += {"-m", std::to_string(config.getMemory())};

        // vcpu
        cmdline += {"-smp", std::to_string(config.getVcpu())};

        // machineInfo
        cmdline += {"-cpu", getMachineType(config.getMachineInfo())};

        // networks

        // drives

        // serialPorts
        {

            bool hasVirtio = false;
            for (auto serialPort : config.getSerialPorts()) {
                if (serialPort.getDriver() == SerialPort::Driver::VIRTIO) hasVirtio = true;
            }
            if (hasVirtio)
                cmdline += {"-device", "virtio-serial-pci"};

            int i = 0;
            for (auto serialPort : config.getSerialPorts()) {
                holders.push_back(std::move(serialPortStreams[i].holder));
                int sock = serialPortStreams[i].fd->fd;
                keepFds.push_back(sock);
                cmdline += {
                    "-add-fd", format("fd=%d,set=%d", sock, sock),
                    "-chardev", format("serial,id=serial%d,path=/dev/fdset/%d", i, sock)
                };
                if (serialPort.getDriver() == SerialPort::Driver::VIRTIO) {
                    cmdline += {
                        "-device",
                        format("virtserialport,chardev=serial%d,name=", i) + qemuQuoteName(serialPort.getName())};
                } else {
                    cmdline += {"-device", format("chardev:serial%d", i)};
                }
                i ++;
            }
        }

        // pciDevices


        std::cerr << cmdline << std::endl;

        subprocess::ProcessBuilder builder (cmdline);
        builder.keepFds = keepFds;
        qemuProcess = builder.start();

        std::cerr << "launched " << qemuProcess->getPid() << std::endl;
        return kj::READY_NOW;
    }
};

class VMServiceImpl : public Service::Server {};

class VMServiceAdminImpl : public VMServiceAdmin::Server {
    Rc<Instance> instance;
public:
    VMServiceAdminImpl(Rc<Instance> instance): instance(instance) {}

    kj::Promise<void> getLauncher(GetLauncherContext context) override {
        context.getResults().setLauncher(kj::heap<VMLauncherImpl>(instance));
        return kj::READY_NOW;
    }
};

}
}

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: metac-vm node-address" << std::endl;
        return 1;
    }

    kj::_::Debug::setLogLevel(kj::_::Debug::Severity::INFO);

    auto instance = metac::createInstance(argv[1]);

    auto req = instance->getThisNodeAdmin().registerNamedServiceRequest();
    req.setName("vm");
    req.setAdminBootstrap(kj::heap<metac::vm::VMServiceAdminImpl>(instance));
    req.setService(kj::heap<metac::vm::VMServiceImpl>());
    auto holder = req.send();
    holder.wait(instance->getWaitScope());

    kj::NEVER_DONE.wait(instance->getWaitScope());
}
