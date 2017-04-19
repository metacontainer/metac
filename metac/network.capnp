@0xa47827dc459cb6c6;

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("metac::network");

using Metac = import "metac.capnp";
using Persistence = import "persistence.capnp";

### High level API

interface NetworkService extends (Metac.Service) {
   vxlanSetup @1 () -> (setup :VxlanSetup);
   # Low-level VXLAN setup
}

interface L2Interface {
   bindTo @0 (other :L2Interface) -> (holder :Persistence.PersistableHolder);
}

### Low level API for other services

const vxlanPort :Int32 = 901; # this should be a privileged port

interface VxlanSetup {
  setup @0 (remote :Metac.NodeAddress, request :AnyPointer) -> (response :Response);
  # Setup bidirectional VXLAN tunnel.
  # - more information will be requested from the `remote` node using RemoteNode(remote).getService("network").vxlanSetup().getRequestInfo(request). This is needed to make sure that its really this node network service who requests this binding.
  # - both src and dst ports must be equal vxlanPort
  # - iface must be an interface created on this node (using createL2Pair).

  getRequestInfo @1 (request :AnyPointer) -> (remote :Metac.NodeAddress, iface :L2Interface, vni :Int32);

  struct Response {
    union {
      ok @0 :Void; # Holder
      vniAlreadyUsed @1 :Void;
    }
  }
}

interface KernelNetworkNamespace {
  # Represents an existing kernel network namespace

  listInterfaces @0 () -> (interfaces :List(KernelInterface));
  # Return a list of network interfaces existing in this namespace

  createInterface @1 (name :Text) -> :KernelInterface;
}

interface KernelInterface {
  # Represents an existing kernel network interface

  getName @0 () -> (name :Text);
  # Name

  destroy @1 ();


  # Attach (unattached) L2Interface to this kernel interface
}

interface NetworkServiceAdmin {
   rootNamespace @0 () -> (namespace :KernelNetworkNamespace);
   # root network namespace
}
