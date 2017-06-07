@0x869358479328c3c3;

using Compute = import "compute.capnp";

interface AgentEnv {

}

interface AgentBootstrap {
  init @0 (env :AgentEnv) -> (envDescription :Compute.ProcessEnvironmentDescription);
}
