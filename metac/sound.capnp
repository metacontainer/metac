@0x9ba093eeb067f146;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

interface Sink {
    bindTo (source :Source) -> (holder :Holder);

    rtpStream @0 () -> (stream :Stream);
}

interface Source {
    bindTo (sink :Sink) -> (holder :Holder);

    rtpStream @0 () -> (stream :Stream);
}

interface HardwareSink extends (Sink) {
    id @0 () -> (id :Text);
}

interface HardwareSource extends (Sources) {
    id @0 () -> (id :Text);
}

interface Mixer {
    # Represents a sound mixer (e.g. PulseAudio instance).

    getMixedSink @0 () -> (sink :Sink);

    getMixedSource @1 () -> (sink :Sink);

    getSinks @2 () -> (sinks :List(HardwareSink))

    getSources @2 () -> (source :List(HardwareSource))
}

interface SoundServerAdmin {
    getDefaultMixer @0 () -> (mixer :Mixer);
}
