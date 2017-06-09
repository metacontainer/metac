@0x9ba093eeb067f146;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

interface SoundDevice {
    # Represents a sound device, either a sink (speaker) or a source (microphone).

    info @0 () -> (info :SoundDeviceInfo);

    opusStream @1 () -> (stream :Stream);
    # Returns stream outputing/accepting audio in OPUS format.

    bindTo @2 (other :SoundDevice) -> (holder :Metac.Holder);
}

struct SoundDeviceInfo {
   name @0 :Text;
   # Name of this device

   isHardware @1 :Bool;
   # Is this real device?

   isSink @2 :Bool;
   # Is this a sink device (as opposed to a source)?
}

interface Mixer {
    # Represents a sound mixer (e.g. PulseAudio instance).

    createSink @0 (name :Text) -> (source :SoundDevice);
    # Create a new sink. Return source which emits sound played on this sink.

    createSource @1 (name :Text) -> (sink :SoundDevice);
    # Create a new source. Audio played on the returned sink will be emitted on this source.

    getSink @2 (name :Text) -> (sink :SoundDevice);
    # Get sink by name.

    getSource @3 (name :Text) -> (source :SoundDevice);
    # Get sink by name.

    getDevices @4 () -> (devs :List(SoundDevice));
    # Get list of currently connected sinks.
}

interface SoundServiceAdmin {
    getSystemMixer @0 () -> (mixer :Mixer);
    # Get system mixer.
    #
    # The default implementation starts a new PulseAudio instance.
}
