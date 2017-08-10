@0xe669517eda764a9f;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

interface Filesystem {
  getSubtree @0 (name :Text) -> (fs :Filesystem);
  # Returns a subtree of this filesystem. `name` may include slashes.
  # `name` may not contain symbolic links.

  getFile @2 (name :Text) -> (file :File);
  # Get file object by name. It doesn't need to exist, the object only represents a path in this filesystem.
  # `name` may not contain symbolic links.

  readonlyFs @3 () -> (fs :Filesystem);
  # Return readonly version of this filesystem.

  # Low level API

  v9fsStream @1 () -> (stream :Stream);
  # Shares this filesystem using v9fs (also called 9p).

  sftpStream @4 () -> (stream :Stream);
  # Shares this filesystem using SFTP protocol.
}

interface FilesystemService extends (Metac.Service) {
  createUnionFilesystem @0 (lower :Filesystem, upper :Filesystem) -> (fs :Filesystem);
}

interface File {
  openAsStream @0 () -> (stream :Stream);

  openAsNbd @1 () -> (stream :Stream);
}

interface FilesystemServiceAdmin {
  rootNamespace @0 () -> (ns :FilesystemNamespace);
}

interface Mount {
  info @0 () -> (path :Text);
}

interface FilesystemNamespace {
  filesystem @0 () -> (fs :Filesystem);

  mount @1 (path :Text, fs :Filesystem) -> (mount :Mount);
  # Mounts filesystem.
  # TODO: nodevmap mount option

  listMounts @2 () -> (mounts :List(Mount));
}
