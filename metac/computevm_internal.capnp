@0x869358479328c3c3;

using Compute = import "compute.capnp";

interface AgentEnv {
  launchProcess @0 (description :Compute.ProcessDescription) -> (process :Compute.Process);
}

interface AgentBootstrap {
  init @0 (env :AgentEnv) -> (envDescription :Compute.ProcessEnvironmentDescription);
}

struct StoredProcessDescription {
  description @0 :Compute.ProcessDescription;
  env @1 :Compute.ProcessEnvironment;
}
