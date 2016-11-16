@0xa31b224f7f6fb23b;

# internal

using Vm = import "vm.capnp";

interface VMInternal extends (Vm.VM) {
  init @0 (config :Vm.LaunchConfiguration) -> (self :VMInternal);
}
