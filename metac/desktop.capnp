@0xc9e97b03b239503a;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;
using Persistence = import "persistence.capnp";
using Fs = import "fs.capnp";

interface Desktop {
    # Desktop represents a remote desktop session - a screen together with mouse/keyboard inputs (and maybe other devices).

    # TODO: recordScreen @1 () -> (video :Video);

    # low level interface
    vncStream @0 () -> (stream :Stream);

    # TODO: add SPICE (or RDP?) support
    # See: https://www.spice-space.org/xspice.html
}

interface WindowSystem {
    # TODO: implement support for "seamless" windows
}

interface DesktopServiceAdmin {
    getDesktopForXSession @0 (address :Text, xauthority :Fs.File) -> (desktop :Desktop);

    # startDesktop @1 (config :DesktopConfig) -> (desktop :Desktop);
}
