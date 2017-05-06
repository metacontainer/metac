@0xc057e9abc4ede86d;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;
using Persistence = import "persistence.capnp";

interface UsbDevice {

    # low level
    usbIpStream @0 () -> (stream :Stream);
}

interface UsbAttachmentTarget {
    attach @0 () -> (holder :PersistableHolder);
}

interface UsbDevices {

}

interface UsbServiceAdmin {
    attachmentTarget @0 () -> (target :UsbAttachmentTarget);

    usbDevices @1 () -> (devices :UsbDevices);
}
