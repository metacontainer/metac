#include <iostream>
#include <capnp/ez-rpc.h>
#include <kj/debug.h>
#include <memory>
#include <unordered_map>
#include "metac/ostools.h"
#include "metac/stlfixes.h"
#include "metac/metac.h"

namespace metac {

class Bridge : public std::enable_shared_from_this<Bridge> {
    typedef std::pair<bool, std::string> InternalServiceId;

    struct InternalService {
        InternalService(Service::Client service, ServiceAdmin::Client admin): service(service), admin(admin) {}
        Service::Client service;
        ServiceAdmin::Client admin;
    };

    std::unordered_map<InternalServiceId, Rc<InternalService>, hash<InternalServiceId> > services;

    struct ServiceHolder : public Holder::Server {
        InternalServiceId id;
        std::weak_ptr<Bridge> bridge;

        ServiceHolder(std::weak_ptr<Bridge> bridge, InternalServiceId id): id(id), bridge(bridge) {}

        ~ServiceHolder() {
            KJ_LOG(INFO, "deleting service", id.second);
            bridge.lock()->services.erase(id);
        }
    };

    friend struct ServiceHolder;

    Rc<InternalService> getService(bool isNamed, std::string name) {
        auto it = services.find({isNamed, name});
        KJ_REQUIRE(it != services.end());
        return it->second;
    }

public:
    std::string nodeAddr;

    Bridge(std::string nodeAddr): nodeAddr(nodeAddr) {}

    ServiceAdmin::Client getServiceAdmin(std::string name) {
        return getService(true, name)->admin;
    }

    Service::Client getService(ServiceId::Reader id) {
        if (id.isAnonymous()) {
            return getService(false, id.getAnonymous())->service;
        } else if (id.isNamed()) {
            return getService(true, id.getNamed())->service;
        } else {
            KJ_REQUIRE(false);
        }
    }

    Holder::Client registerService(bool isNamed, std::string name,
                                   Service::Client service,
                                   ServiceAdmin::Client admin) {
        KJ_LOG(INFO, "registering service", name);
        services[{isNamed, name}] = std::make_shared<InternalService>(service, admin);
        return kj::heap<ServiceHolder>(shared_from_this(), InternalServiceId{isNamed, name});
    }
};

class NodeImpl : public Node::Server {
    Rc<Bridge> bridge;
public:
    NodeImpl(Rc<Bridge> bridge): bridge(bridge) {}

    kj::Promise<void> address(AddressContext context) override {
        context.getResults().getAddress().setIp(bridge->nodeAddr);
        return kj::READY_NOW;
    }


    kj::Promise<void> getService(GetServiceContext context) override {
        auto service = bridge->getService(context.getParams().getId());
        context.getResults().setService(service);
        return kj::READY_NOW;
    }

    kj::Promise<void> registerAnonymousService(RegisterAnonymousServiceContext context) override {
        std::string id = randomHexString(32);
        auto holder = bridge->registerService(false, id,
                                              context.getParams().getService(),
                                              nullptr);

        context.getResults().getId().setAnonymous(id);
        context.getResults().setHolder(holder);
        return kj::READY_NOW;
    }
};

class NodeAdminImpl : public NodeAdmin::Server {
    Rc<Bridge> bridge;
public:
    NodeAdminImpl(Rc<Bridge> bridge): bridge(bridge) {}

    kj::Promise<void> getServiceAdmin(GetServiceAdminContext context) override {
        auto admin = bridge->getServiceAdmin(context.getParams().getName());
        context.getResults().setService(admin);
        return kj::READY_NOW;
    }

    kj::Promise<void> registerNamedService(RegisterNamedServiceContext context) override {
        auto holder = bridge->registerService(true, context.getParams().getName(),
                                              context.getParams().getService(),
                                              context.getParams().getAdminBootstrap());
        context.getResults().setHolder(holder);
        return kj::READY_NOW;
    }

    kj::Promise<void> getUnprivilegedNode(GetUnprivilegedNodeContext context) override {
        context.getResults().setNode(kj::heap<NodeImpl>(bridge));
        return kj::READY_NOW;
    }
};

}

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: metac-bridge node-address" << std::endl;
        return 1;
    }

    kj::_::Debug::setLogLevel(kj::_::Debug::Severity::INFO);

    std::string nodeAddr = argv[1];
    std::string baseDir = "/run/metac/" + nodeAddr;

    auto bridge = std::make_shared<metac::Bridge>(nodeAddr);

    metac::createDir("/run/metac");
    metac::createDir(baseDir);

    auto sockPath = baseDir + "/socket";
    metac::unlink(sockPath);

    capnp::EzRpcServer serverUnix (kj::heap<metac::NodeAdminImpl>(bridge), "unix:" + sockPath);
    capnp::EzRpcServer serverTcp (kj::heap<metac::NodeImpl>(bridge), "[" + nodeAddr + "]:901");
    kj::NEVER_DONE.wait(serverTcp.getWaitScope());
}
