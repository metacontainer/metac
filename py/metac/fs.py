from metac.core import *
from typing import NamedTuple, Optional
from enum import Enum
import urllib.parse, os

class FileRef(Ref):
    pass

class FilesystemRef(Ref):
    pass

class BlockDevMount(NamedTuple):
    dev: FileRef
    offset: int

class Mount(NamedTuple):
    path: str
    persistent: bool = False
    readonly: bool = False

    fs: Optional[FilesystemRef] = None
    blockDev: Optional[BlockDevMount] = None

class MountRef(Ref, GetMixin[Mount], UpdateMixin[Mount], DeleteMixin):
    value_type = Mount

class MountCollection(Ref, CollectionMixin[Mount, MountRef]):
    value_type = Mount
    ref_type = MountRef

class FilesystemNamespaceRef(Ref):
    @property
    def mounts(self) -> MountCollection:
        return MountCollection(self.rpath + 'mounts/')

def get_file(path):
    return FileRef('/fs/file/%s/' % urllib.parse.quote(os.path.realpath(path), safe=''))

def get_fs(path):
    return FilesystemRef('/fs/fs/%s/' % urllib.parse.quote(os.path.realpath(path), safe=''))

def get_mounts():
    return MountCollection('/fs/mounts/')

if __name__ == '__main__':
    print(get_mounts().values())
