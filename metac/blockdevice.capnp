@0xc3cb6fa19db40c30;

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("metac");

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

interface BlockDevice {
  # Represents a block device (e.g. a disk)

  # Low level interface
  ndbSetup @0 () -> (stream :Stream);
}
