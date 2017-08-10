@0x9ba093eeb067f146;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

# For service users.

interface PersistenceService extends (Metac.Service) {

}

interface Persistable extends (Metac.Waitable) {
  createSturdyRef @0 (rgroup :Metac.ResourceGroup, persistent :Bool) -> (id :Metac.MetacSturdyRef);
  # Create unguessable reference to this object and return it.

  summary @1 () -> (info :Text);
  # Return human readable description.
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

struct PersistentObjectInfo {
   service @1 :Text;

   category @2 :Text;

   runtimeId @4 :Text;

   persistent @3 :Bool;

   summary @5 :Text;

   references @0 :List(Text);
}

struct SturdyRefInfo {
   sturdyRef @0 :Metac.MetacSturdyRef;
}

interface PersistenceServiceAdmin {
   getHandlerFor @0 (service :Metac.ServiceId) -> (handler :ServicePersistenceHandler);

   listObjects @1 () -> (infos :List(PersistentObjectInfo));

   listReferences @3 (service :Text, runtimeId :Text) -> (infos :List(SturdyRefInfo));

   forgetObject @2 (service :Text, runtimeId :Text);
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
