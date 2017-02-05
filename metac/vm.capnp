@0xc1122ecaf8f1f29e;

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("metac::vm");

using Metac = import "metac.capnp";
using Net = import "network.capnp";
using Stream = import "stream.capnp";
using Fs = import "fs.capnp";

using BlockDevice = import "blockdevice.capnp".BlockDevice;

struct LaunchConfiguration {
  struct KernelBoot {
    kernel @0 :Fs.File;
    initrd @1 :Fs.File;
    flags @2 :Text;
  }

  struct Boot {
    union {
      kernel @0 :KernelBoot;
      disk @1 :Int32;
    }
  }

  boot @0 :Boot;

  memory @1 :Int32;
  # Available memory, in MiB

  vcpu @2 :Int32;
  # CPU cores

  machineInfo @3 :MachineInfo;
  # CPU identification

  networks @4 :List(Network);
  # List of attached networks.

  drives @5 :List(Drive);
  # List of attached drives.

  serialPorts @6 :List(SerialPort);
  # List of attached serial ports.

  pciDevices @7 :List(PciDeviceAttachment);
  # List of attached PCI devices.
}

struct MachineInfo {
  enum Type {
    kvm64 @0;
    host @1;
  }

  type @0 :Type;
  # Machine type

  hideVm @1 :Bool;
  # Pretend to guest that he is not in a VM.
}

struct Network {
  enum Driver {
    virtio @0;
  }
  driver @0 :Driver;
  network @1 :Net.L2Interface;
}

struct Drive {
  enum Driver {
    virtio @0;
  }
  driver @0 :Driver;
  device @1 :BlockDevice;
}

struct SerialPort {
  enum Driver {
    default @0;
    virtio @1;
  }
  driver @0 :Driver;
  stream @1 :Stream.Stream;
  name @2 :Text;
}

interface VM extends (Metac.Pinnable, Metac.Persistent) {
  stop @0 ();
}

interface VMLauncher {
  launch @0 (config :LaunchConfiguration) -> (vm :VM);
  # Launches a virtual machine.
}

interface VMServiceAdmin extends (Metac.ServiceAdmin) {
  getPinnedVMs @0 () -> (vms :List(VM));
  # Get pinned VMs

  getPciDevices @1 () -> (devices :List(PciDevice));
  # Get list of PCI devices (for passing to the VMs)

  getLauncher @2 () -> (launcher :VMLauncher);
  # Get instance of a launcher that can be used to launch VMs on this host.
}

# PCI devices

struct PciDeviceAttachment {
  device @0 :PciDevice;
  # Reference to the PCI device. Must be on the same host.

  guestAddress @1 :Text;
  # Guest PCI address (like 01:00.1).
}

interface PciDevice {

}
