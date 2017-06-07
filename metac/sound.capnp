@0x9ba093eeb067f146;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

interface Sink {
    # Represents a sound sink (e.g. a speaker).

    info @0 () -> (info :SoundDeviceInfo);

    bindTo @1 (source :Source) -> (holder :Metac.Holder);
    # Bind this sink to a source.

    opusStream @2 () -> (stream :Stream);
    # Returns stream accepting audio in OPUS format
}

interface Source {
    # Represents a sound source (e.g. a microphone).

    info @0 () -> (info :SoundDeviceInfo);

    opusStream @1 () -> (stream :Stream);
    # Returns stream outputing audio in OPUS format.
}

struct SoundDeviceInfo {
   name @0 :Text;
   # Name of this device

   isHardware @1 :Bool;
   # Is this real device?
}


interface Mixer {
    # Represents a sound mixer (e.g. PulseAudio instance).

    createSink @0 (name :Text) -> (source :Source);
    # Create a new sink. Return source which emits sound played on this sink.

    createSource @1 (name :Text) -> (sink :Sink);
    # Create a new source. Audio played on the returned sink will be emitted on this source.

    getSinks @2 () -> (sinks :List(Sink));
    # Get list of currently connected sinks.

    getSources @3 () -> (source :List(Source));
    # Get list of currently connected sources.
}

interface SoundServerAdmin {
    getSystemMixer @0 () -> (mixer :Mixer);
    # Get system mixer.
    #
    # The default implementation starts a new PulseAudio instance.
}
