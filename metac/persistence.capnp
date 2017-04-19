@0x9ba093eeb067f146;

using Metac = import "metac.capnp";
using Stream = import "stream.capnp".Stream;

# For service users.

interface PersistenceService extends (Service) {

}

interface Persistable {
   createSturdyRef @0 (rgroup :Metac.ResourceGroup) -> (id :MetacSturdyRef);
   # Create unguessable reference to this object and return it.

   persist @1 (rgroup :Metac.ResourceGroup);
   # Mark this object to be persistent between reboots.
}

interface PersistableHolder extends (Persistable, Holder) {

}

# For service authors.

interface Restorer {
   restoreFromDescription @0 (description :AnyPointer) -> :AnyPointer;
}

interface PersistenceServiceAdmin {
   getHandlerFor @0 (service :Metac.ServiceId) -> (handler :ServicePersistenceHandler);
}

interface ServicePersistenceHandler {
   registerRestorer @0 (restorer :Restorer);

   saveCap @0 (group :PersistenceGroup, description :AnyPointer, cap :AnyPointer) -> :Metac.MetacSturdyRef;
}
