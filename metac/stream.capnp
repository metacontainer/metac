@0xc75eeff875deb52e;

using Metac = import "metac.capnp";

interface Stream {
  # Represents potentially bidirectional stream of bytes.

  tcpListen @0 (remote :Metac.NodeAddress, port :Int32) -> (local :Metac.NodeAddress, port :Int32, holder :Metac.Holder);
  # Request the node owning the stream to listen accepting exactly one TCP connection from 'remote:port'. Connections from other addresses will be dropped. Caller of this method should bind port `remotePort` before making this call---this ensures that no one unauthrized will be able to connect.

  bindTo @1 (other :Stream) -> (holder :Metac.Holder);
  # Pipe all data between this and 'other' stream.
}
