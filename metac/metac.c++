#include "metac/metac.h"
#include <capnp/ez-rpc.h>
#include <unistd.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <kj/debug.h>
#include <algorithm>

namespace metac {

class InstanceImpl : public Instance {
    // it is important that the client outlives all references
    kj::Own<capnp::EzRpcClient> client;
    Node::Client thisNode;
    NodeAdmin::Client thisNodeAdmin;
    std::string nodeAddress;
    bool isAdmin;

public:
    InstanceImpl(Node::Client thisNode, NodeAdmin::Client thisNodeAdmin, kj::Own<capnp::EzRpcClient> client, std::string nodeAddress, bool isAdmin):
        client(std::move(client)), thisNode(thisNode), thisNodeAdmin(thisNodeAdmin), nodeAddress(nodeAddress), isAdmin(isAdmin) {

    }

    NodeAdmin::Client getThisNodeAdmin() override {
        KJ_REQUIRE(isAdmin);
        return thisNodeAdmin;
    }

    Node::Client getThisNode() override { return thisNode;}

    std::string getNodeAddress() override {
        return nodeAddress;
    }

    kj::AsyncIoProvider& getIoProvider() override {
        return client->getIoProvider();
    }

    kj::LowLevelAsyncIoProvider& getLowLevelIoProvider() override {
        return client->getLowLevelIoProvider();
    }

    kj::WaitScope& getWaitScope() override {
        return client->getWaitScope();
    }

    kj::Own<kj::NetworkAddress> getAddressFromIp(std::string ip) override {
        // Validating IP address is important, otherwise anyone could force us to connect to any UNIX socket etc.
        // TODO: check if IP is a backplane address
        bool isV6 = std::find(ip.begin(), ip.end(), ':') != ip.end();

        sockaddr_storage ss;
        ss.ss_family = isV6 ? AF_INET6 : AF_INET;
        int ret = inet_pton(ss.ss_family, ip.c_str(),
                            isV6 ? (void*)(&((sockaddr_in6*)&ss)->sin6_addr) : (void*)(&((sockaddr_in*)&ss)->sin_addr));
        KJ_REQUIRE(ret == 1, "invalid IP address");
        return getIoProvider().getNetwork().getSockaddr(&ss, sizeof(ss));
    }
};

Rc<Instance> createInstance(std::string nodeAddress) {
    bool isAdmin = getuid() == 0;
    std::string address = isAdmin ? ("unix:/run/metac/" + nodeAddress + "/socket") : (nodeAddress + ":901");

    auto client = kj::heap<capnp::EzRpcClient>(address);

    NodeAdmin::Client thisNodeAdmin = nullptr;
    Node::Client thisNode = nullptr;

    if (isAdmin) {
        thisNodeAdmin = client->getMain<NodeAdmin::Client>();

        auto request = thisNodeAdmin.getUnprivilegedNodeRequest();
        thisNode = request.send().wait(client->getWaitScope()).getNode();
    } else {
        thisNode = client->getMain<Node::Client>();
    }

    std::string canonicalNodeAddress = thisNode.addressRequest().send().wait(client->getWaitScope()).getAddress().getIp();

    return std::make_shared<InstanceImpl>(thisNode, thisNodeAdmin, std::move(client), canonicalNodeAddress, isAdmin);
}

struct RcHolder : public Holder::Server {
    Rc<void> object;
    RcHolder(Rc<void> object): object(object) {}
};

Holder::Client rcHolder(Rc<void> object) {
    return kj::heap<RcHolder>(object);
}
}
