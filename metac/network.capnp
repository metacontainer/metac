@0xa47827dc459cb6c6;

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("metac::network");

using Metac = import "metac.capnp";
using Persistence = import "persistence.capnp";

### High level API

interface NetworkService extends (Metac.Service) {
   vxlanSetup @0 () -> (setup :VxlanSetup);
   # Low-level VXLAN setup
}

interface L2Interface {
  bindTo @0 (other :L2Interface) -> (holder :Metac.Holder);

  # low level interface
  setupVxlan @1 (remote :Metac.NodeAddress, request :AnyPointer) -> (response :VxlanSetup.Response);
}

### Low level API for other services

const vxlanPort :Int32 = 901; # this should be a privileged port

interface VxlanSetup {
  # Setup bidirectional VXLAN tunnel.
  # - more information will be requested from the `remote` node using RemoteNode(remote).getService("network").vxlanSetup().getRequestInfo(request). This is needed to make sure that its really this node network service who requests this binding.
  # - both src and dst ports must be equal vxlanPort

  getRequestInfo @0 (request :AnyPointer) -> (remote :Metac.NodeAddress, iface :L2Interface, vni :Int32);

  struct Response {
    union {
      ok @0 :Metac.Holder;
      vniAlreadyUsed @1 :Void;
    }
  }
}

interface KernelNetworkNamespace {
  # Represents an existing kernel network namespace

  listInterfaces @0 () -> (interfaces :List(KernelInterface));
  # Return a list of network interfaces existing in this namespace

  createInterface @1 (name :Text) -> (iface :KernelInterface);
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

interface NetworkServiceAdmin {
   rootNamespace @0 () -> (namespace :KernelNetworkNamespace);
   # root network namespace
}
