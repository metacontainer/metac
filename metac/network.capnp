@0xa47827dc459cb6c6;

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("metac::network");

using Metac = import "metac.capnp";
using Persistence = import "persistence.capnp";

### High level API

interface L2Interface {
  bindTo @0 (other :L2Interface) -> (holder :Metac.Holder);
  # Pipe all traffic between this and 'other' interface.

  setupVxlan @1 (remote :Metac.NodeAddress, dstPort :UInt16, vniNum :UInt32) -> (local :Metac.NodeAddress, srcPort :UInt16, holder :Metac.Holder);
  # Setup unicast VXLAN connection between 'remote' and node hosting this L2Interface. 'dstPort' and 'srcPort' should be unique and not used for any other UDP communication. 'vniNum' is used as an additional 24-bit secret value (not strictly neccessary, but won't harm).
}

### Low level API for other services

interface NetworkServiceAdmin {
   rootNamespace @0 () -> (namespace :KernelNetworkNamespace);
   # root network namespace
}

interface KernelNetworkNamespace {
  # Represents an existing kernel network namespace

  listInterfaces @0 () -> (interfaces :List(KernelInterface));
  # Return a list of network interfaces existing in this namespace

  getInterface @1 (name :Text) -> (iface :KernelInterface);
  # Return an existing kernel interface.

  createInterface @2 (name :Text) -> (iface :KernelInterface);
  # Create a new kernel interface. Actual creation of the interface may be delayed until it is bound to something.
}

interface KernelInterface {
  # Represents an existing kernel network interface

  getName @0 () -> (name :Text);
  # Name

  isHardware @4 () -> (isHardware :Bool);

  rename @3 (newname :Text);
  # Change name

  destroy @1 ();
  # Delete the interface

  l2Interface @2 () -> (iface :L2Interface);
  # Return L2Interface associated with this kernel interface
}
