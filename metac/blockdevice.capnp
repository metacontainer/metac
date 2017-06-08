@0xc3cb6fa19db40c30;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

interface BlockDevice {
  # Represents a block device (e.g. a disk)

  # Low level interface
  nbdSetup @0 () -> (stream :Stream);
}
