@0xd73ed8e6c5ada477;

### Common structs

struct NodeAddress {
  ip @0 :Text;
}

struct ServiceId {
  union {
    named @0 :Text;
    # named service (like network, usb etc)

    anonymous @1 :Text;
    # unnamed service represented by a random string
  }
}

struct MetacSturdyRef {
  # SturdyRef is a saved (possibly persistent) capability identifier.

  node @0 :NodeAddress;
  service @1 :ServiceId;
  objectInfo @2 :AnyPointer;
}

struct TypedAnyPointer {
  type @0 :UInt64;
  val @1 :AnyPointer;
}

struct NewMetacSturdyRef {
  # SturdyRef is a saved (possibly persistent) capability identifier.

  node @0 :List(NodeAddress);
  # Any of these nodes should be able to restore this ref.

  service @1 :ServiceId;
  objectInfo @2 :AnyPointer;

  extra @3 :List(TypedAnyPointer);
  # Extra information, for e.g. restoring the capability using a local plugin.
}

### Bootstrap interfaces

interface ServiceAdmin {}

interface Holder {}

interface Waitable {
  wait @0 ();
  # Wait until the held object is destroyed.
  # In case of failure (e.g. host responsible for this cap is rebooted) error should be returned.
}

interface Destroyable {
  destroy @0 ();
}

interface ResourceGroup {
  # Resource group is used for accounting and rate limiting.

}

interface NodeAdmin {
  # Bootstrap interface for superusers. Exposes everything that is possible to do on this node.

  getServiceAdmin @0 (name :Text) -> (service :ServiceAdmin);
  # Returns admin bootstrap interface for a named service.

  registerNamedService @1 (name :Text, service :Service, adminBootstrap :ServiceAdmin) -> (holder :Holder);
  # Registers a new named service.

  getUnprivilegedNode @2 () -> (node :Node);
}

interface Node {
  address @0 () -> (address :NodeAddress);

  getService @1 (id :ServiceId) -> (service :Service);
  # Returns a service object for a given service id.

  waitForService @3 (id :ServiceId);
  # Wait for service to become available.

  registerAnonymousService @2 (service :Service) -> (id :ServiceId, holder :Holder);
  # Registers an anonymous service.
  # This number of invokations of this method may be limited to avoid resource exhaustion attacks.
}

interface Service {
   restore @0 (objectInfo :AnyPointer) -> (obj :AnyPointer);
   # Restores a SturdyRef associated with this service.
}

interface CastToLocal {
   # Internal implementation interface.
   # Until Level 4 is implemented in capnproto, we need a way to change capability into our local object.
   registerLocal @0 (id :Text);
}
