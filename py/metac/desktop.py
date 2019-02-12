from metac.core import *
from typing import NamedTuple, Optional

class Desktop(NamedTuple):
    supportedFormats: List[str]

class DesktopRef(Ref, GetMixin[Desktop]):
    value_type = Desktop

class X11Desktop(NamedTuple):
    meta: Metadata
    displayId: Optional[str]
    xauthorityPath: Optional[str]
    virtual: bool

class X11DesktopRef(Ref, GetMixin[Desktop], UpdateMixin[Desktop]):
    value_type = X11Desktop

class X11DesktopCollection(Ref, CollectionMixin[Desktop, DesktopRef]):
    value_type = X11Desktop
    ref_type = X11DesktopRef

def get_desktops():
    return X11DesktopCollection('/x11-desktop/')

if __name__ == '__main__':
    for k in get_desktops().values():
        print(k)
        print('-->', k.get())
