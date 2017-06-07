@0xc057e9abc4ede86d;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;
using Persistence = import "persistence.capnp";

interface UsbDevice {
    struct Info {
        busId @0 :Text;
        productId @1 :Text;
    }

    info @0 () -> (info :Info);
    # Get information about this device.

    usbIpStream @1 () -> (stream :Stream);
    # Open USB-IP stream to this device.
}

interface UsbAttachmentTarget {
    attach @0 (device :UsbDevice) -> (holder :Metac.Holder);
    # Attach a remote USB device.
}

interface UsbDevices {
   listDevices @0 () -> (devices :List(UsbDevice));
   # List all USB device connected to this host.

   getDeviceByProductId @1 (productId :Text) -> (device :List(UsbDevice));
   # Get device with this 'productId'. The object will be returned even if there is no currently connected device or there are multiple devices with the same product id.
}

interface UsbServiceAdmin {
    attachmentTarget @0 () -> (target :UsbAttachmentTarget);
    # Attach new USB devices to this host.

    usbDevices @1 () -> (devices :UsbDevices);
    # Access USB devices connected to this host.
}
