#ifndef _METAC_METAC_H
#define _METAC_METAC_H
#include "metac/metac.capnp.h"
#include "metac/stlfixes.h"
#include <kj/async-io.h>

namespace metac {

class Instance {
public:
    virtual Node::Client getThisNode() = 0;
    virtual NodeAdmin::Client getThisNodeAdmin() = 0;
    virtual std::string getNodeAddress() = 0;
    virtual kj::AsyncIoProvider& getIoProvider() = 0;
    virtual kj::LowLevelAsyncIoProvider& getLowLevelIoProvider() = 0;
    virtual kj::WaitScope& getWaitScope() = 0;

    virtual kj::Own<kj::NetworkAddress> getAddressFromIp(std::string ip) = 0;
};

Rc<Instance> createInstance(std::string nodeAddress);

Holder::Client rcHolder(Rc<void> object);
// Returns capability which sole purpose is keeping `object` alive.
};

#endif
