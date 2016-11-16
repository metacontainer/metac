@0xe669517eda764a9f;

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("metac::fs");

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;
using BlockDevice = import "blockdevice.capnp".BlockDevice;

interface Filesystem {
  getSubtree @0 (name :Text) -> (fs :Filesystem);
  # Returns a subtree of this filesystem. `name` may include slashes.
  # `name` may not contain symbolic links.

  getFile @2 (name :Text) -> (file :File);
  # Get file object by name. It doesn't need to exist, the object only represents a path in this filesystem.
  # `name` may not contain symbolic links.

  # Low level API

  v9fsStream @1 () -> (stream :Stream);
  # Shares this filesystem using v9fs (also called 9p).
}

interface FilesystemService extends (Metac.Service) {
  createUnionFilesystem @0 (lower :Filesystem, upper :Filesystem) -> (fs :Filesystem);
}

interface File {
  openAsStream @0 () -> (stream :Stream);

  openAsBlock @1 () -> (device :BlockDevice);
}

# Low level API

interface FilesystemServiceAdmin {
  rootNamespace @0 () -> (ns :FilesystemNamespace);
}

interface FilesystemNamespace {
  filesystem @0 () -> (fs :Filesystem);

  mount @1 (path :Text, fs :Filesystem);
  # Mounts filesystem.

  unmount @2 (path :Text) -> (ok :Bool);
  # Unmounts filesystem.
}
