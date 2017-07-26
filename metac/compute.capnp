@0x94f1b7258366ae48;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;
using Net = import "network.capnp";
using Fs = import "fs.capnp";

interface ComputeLauncher {
  launch @0 (processDescription :ProcessDescription,
             envDescription :ProcessEnvironmentDescription) -> (env :ProcessEnvironment, process :Process);
  # Launch a process in a new process environment.
}

struct ProcessEnvironmentDescription {
  # Represents a description of an environment (e.g. container) for running processes.

  filesystems @0 :List(FsMount);
  # List of filesystems to mount.

  networks @1 :List(NetworkInterface);
  # List of network interfaces to attach.

  memory @2 :UInt32;
  # Memory allocation for this environment (in MiB).
}

struct FsMount {
  path @0 :Text;
  # Where to mount this filesystem? Use '/' for root filesystem.

  fs @1 :Fs.Filesystem;
  # The filesystem.
}

struct NetworkInterface {
  name @0 :Text;
  # Name of the network interface.

  l2interface @1 :Net.L2Interface;
  # If null, new network will be created, later available via 'ProcessEnvironment.network' method.

  struct Route {
    network @0 :Text;
    # Address of the network (e.g. 192.168.0.0/24)
    via @1 :Text;
    # Gateway. If null, direct route will be created.
  }

  addresses @2 :List(Text);
  # List of IP address for this interface.

  routes @3 :List(Route);
  # List of routes exiting via this interface.
}

struct ProcessDescription {
  files @0 :List(FD);
  # Open FDs.

  args @1 :List(Text);
  # Arguments, including executable name.

  uid @2 :UInt32;
  gid @3 :UInt32;
  # User and group identifier for this process.
}

struct FD {
  isPty @0 :Bool;
  # Should the file descriptor be opened as a virtual terminal?
  # If isPty is true, this FD will use the Simple PTY Protocol.

  stream @1 :Stream;
  # The stream. If null, new stream will be created, later accessible via 'Process.files' method.

  targets @2 :List(UInt32);
  # List of file descriptor numbers to bind in the target process.
}

interface Process {
  file @0 (index :UInt32) -> (stream :Stream);
  # Returns stream for file previously specified in 'files' property of 'ProcessDescription'.

  kill @1 (signal :UInt32);
  # Kill the process.

  returnCode @2 () -> (code :Int32);
  # If the process has finished, return its return code.

  wait @3 ();
  # Wait for process to finish.
}

interface ProcessEnvironment {
  launchProcess @0 (processDescription :ProcessDescription) -> (process :Process);
  # Launch a new process in this environment.

  network @1 (index :UInt32) -> (iface :Net.L2Interface);
  # Return network specified in ProcessEnvironmentDescription with index 'index'.
}
