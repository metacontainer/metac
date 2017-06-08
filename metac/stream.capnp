@0xc75eeff875deb52e;

using Metac = import "metac.capnp";

interface Stream {
  # Represents potentially bidirectional stream of bytes.

  tcpListen @0 (remote :Metac.NodeAddress, port :Int32) -> (local :Metac.NodeAddress, port :Int32, holder :Metac.Holder);
  # Order the node owning the stream to listen accepting exactly one TCP connection from 'remote:port'.
}
