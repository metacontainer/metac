@0x9ba093eeb067f146;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

# For service users.

interface PersistenceService extends (Metac.Service) {

}

interface Persistable {
  createSturdyRef @0 (rgroup :Metac.ResourceGroup, persistent :Bool) -> (id :Metac.MetacSturdyRef);
  # Create unguessable reference to this object and return it.

  # wait @1 ();
  # Wait until the held object is destroyed.
  # In case of failure (e.g. host responsible for this cap is rebooted) errors should be returned.
}

# For service authors.

struct CapDescription {
   runtimeId @0 :Text;
   category @1 :Text;
   description @2 :AnyPointer;
}

interface Restorer {
   restoreFromDescription @0 (description :CapDescription) -> (cap :AnyPointer);
}

interface PersistenceServiceAdmin {
   getHandlerFor @0 (service :Metac.ServiceId) -> (handler :ServicePersistenceHandler);
}

interface ServicePersistenceHandler {
   registerRestorer @0 (restorer :Restorer);

   createSturdyRef @1 (
                   group :Metac.ResourceGroup,
                   description :CapDescription,
                   persistent :Bool,
                   cap :AnyPointer) -> (ref :Metac.MetacSturdyRef);
}

struct PersistentPayload {
    content @0 :AnyPointer;

    capTable @1 :List(Metac.MetacSturdyRef);
}

struct Call {
   cap @0 :AnyPointer;

   interfaceId @1 :UInt64;

   methodId @2 :UInt64;

   args @3 :AnyPointer;
}
