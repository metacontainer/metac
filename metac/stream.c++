#include "metac/stream.h"
#include <kj/debug.h>
#include "metac/kjfixes.h"
#include "metac/kjstreamproxy.h"

namespace metac {

class WrappedStream : public Stream::Server {
    StreamProvider streamProvider;
    Rc<Instance> instance;

    class TcpListener : public std::enable_shared_from_this<TcpListener> {
        kj::Own<kj::AsyncIoStream> stream;
        Rc<Instance> instance;
        kj::Own<kj::ConnectionReceiver> acceptor;
        kj::Maybe<kj::Promise<void> > currentListener;
        kj::Maybe<kj::Own<kjfixes::Piper> > piper;

        kj::Promise<void> receiveNextConnection() {
            return acceptor->accept().then([this](kj::Own<kj::AsyncIoStream> remoteStream) -> kj::Promise<void> {
                auto peerId = kjfixes::getPeerName(remoteStream);
                if (peerId == std::make_pair(remoteIp, remotePort)) {
                    KJ_LOG(INFO, "got TCP connection");
                    piper = kjfixes::pipe(std::move(stream), std::move(remoteStream));
                    return kj::READY_NOW;
                } else {
                    auto peerIp = peerId.first;
                    auto peerPort = peerId.second;
                    KJ_LOG(WARNING, "got connection from bad peer", peerIp, peerPort, remoteIp, remotePort);
                    return receiveNextConnection();
                }
            });
        }

    public:
        int32_t localPort;
        int32_t remotePort;
        std::string remoteIp;

        TcpListener(kj::Own<kj::AsyncIoStream> stream, Rc<Instance> instance, int32_t remotePort, std::string remoteIp): stream(std::move(stream)), instance(instance), remotePort(remotePort), remoteIp(remoteIp) {

            acceptor = instance->getAddressFromIp(instance->getNodeAddress())->listen();
            localPort = acceptor->getPort();
            KJ_LOG(INFO, "setting up listener on", instance->getNodeAddress(), localPort);

            currentListener = receiveNextConnection();
        }
    };
    
public:
    WrappedStream(Rc<Instance> instance, StreamProvider streamProvider): streamProvider(std::move(streamProvider)), instance(instance) {}

    kj::Promise<void> tcpListen(TcpListenContext context) {
        return streamProvider().then([context, this] (auto stream) mutable {
            std::string ip = context.getParams().getRemote().getIp();
            int32_t port = context.getParams().getPort();

            auto listener = std::make_shared<TcpListener>(std::move(stream), instance, port, ip);

            context.getResults().setPort(listener->localPort);
            context.getResults().getLocal().setIp(instance->getNodeAddress());
            context.getResults().setHolder(rcHolder(listener));
        });
    }
};

Stream::Client wrapStream(Rc<Instance> instance, StreamProvider stream) {
    return kj::heap<WrappedStream>(instance, std::move(stream));
}

Stream::Client wrapStream(Rc<Instance> instance, kj::Own<kj::AsyncIoStream> stream) {
    auto streamWrapper = std::make_shared<std::pair<bool, kj::Own<kj::AsyncIoStream> > >(false, std::move(stream));
    auto func = [streamWrapper] () mutable -> kj::Promise<kj::Own<kj::AsyncIoStream> > {
        KJ_REQUIRE(!streamWrapper->first, "this stream is already consumed");
        streamWrapper->first = true;
        return std::move(streamWrapper->second);
    };
    return kj::heap<WrappedStream>(instance, func);
}

kj::Promise<kj::Own<kj::AsyncIoStream> > unwrapStream(Rc<Instance> instance, Stream::Client stream) {
    std::string selfAddr = instance->getNodeAddress();

    auto socket = kjfixes::bindStreamSocket(instance->getLowLevelIoProvider(),
                                            instance->getAddressFromIp(selfAddr));
    auto req = stream.tcpListenRequest();
    req.getRemote().setIp(selfAddr);
    req.setPort(socket->getPort());

    return req.send().then([instance, socket{std::move(socket)}] (auto res) mutable {
        std::string remoteAddr = res.getLocal().getIp();
        int remotePort = res.getPort();
        KJ_REQUIRE(remotePort > 1024);
        Holder::Client holder = res.getHolder();
        KJ_LOG(INFO, "connecting to", remoteAddr, remotePort);

        return socket->connect(instance->getAddressFromIp(remoteAddr), remotePort).then([holder] (kj::Own<kj::AsyncIoStream> connected) mutable -> kj::Own<kj::AsyncIoStream> {
            return kj::heap<AsyncIoStreamProxy<Holder::Client> >(std::move(connected), holder);
        });
    });
}
}
