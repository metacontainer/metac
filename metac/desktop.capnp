@0xc9e97b03b239503a;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;
using Persistence = import "persistence.capnp";

interface Desktop {
    # Desktop represents a remote desktop session - a screen together with mouse/keyboard inputs (and maybe other devices).

    # TODO; recordScreen @1 () -> (video :Video);

    # low level interface
    vncStream @0 () -> (stream :Stream);
}

interface WindowSystem {
}

interface DesktopAdmin {
    getDesktopForXSession @0 (num :Int32) -> (desktop :Desktop);

    # startDesktop @1 (config :DesktopConfig) -> (desktop :Desktop);
}
