#include "metac/kjfixes.h"
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <string>
#include <algorithm>
#include "metac/kjstreamproxy.h"

namespace kjfixes {
std::pair<std::string, int> getPeerName(kj::Own<kj::AsyncIoStream>& sock) {
    sockaddr_storage addr;
    socklen_t size = sizeof(sockaddr_storage);
    sock->getpeername((sockaddr*)(&addr), &size);
    void* addr_info;
    short port;
    if (addr.ss_family == AF_INET) {
        addr_info = &(((sockaddr_in*)&addr)->sin_addr);
        port = ((sockaddr_in*)&addr)->sin_port;
    } else if(addr.ss_family == AF_INET6) {
        addr_info = &(((sockaddr_in6*)&addr)->sin6_addr);
        port = ((sockaddr_in6*)&addr)->sin6_port;
    } else {
        return {"", 0};
    }

    char s[INET6_ADDRSTRLEN];
    const char* ret = inet_ntop(addr.ss_family, addr_info, s, sizeof(s));
    KJ_ASSERT(ret != NULL);

    return {std::string(s), htons(port)};
}

class PiperImpl : public Piper {
    kj::Own<kj::AsyncIoStream> streamA;
    kj::Own<kj::AsyncIoStream> streamB;
    kj::Maybe<kj::Promise<void> > pipe1;
    kj::Maybe<kj::Promise<void> > pipe2;
    static const int BUFFER_SIZE = 4096;
    char buffer1[BUFFER_SIZE];
    char buffer2[BUFFER_SIZE];

    kj::Promise<void> pipeFrom(kj::Own<kj::AsyncIoStream>& stream1, kj::Own<kj::AsyncIoStream>& stream2, char* buffer) {
        return stream1->tryRead(buffer, 1, BUFFER_SIZE).then([this, &stream1, &stream2, buffer](size_t s) -> kj::Promise<void> {
            if (s == 0) {
                stream2->shutdownWrite();
                return kj::READY_NOW;
            }
            KJ_ASSERT(s <= BUFFER_SIZE);
            return stream2->write(buffer, s);
        }).then([this, &stream1, &stream2, buffer]() -> kj::Promise<void> {
            return pipeFrom(stream1, stream2, buffer);
        });
    }

    public:
    PiperImpl(kj::Own<kj::AsyncIoStream> streamA, kj::Own<kj::AsyncIoStream> streamB) : streamA(std::move(streamA)), streamB(std::move(streamB)) {
        pipe1 = pipeFrom(this->streamA, this->streamB, buffer1);
        pipe2 = pipeFrom(this->streamB, this->streamA, buffer2);
    }
    ~PiperImpl() noexcept {}
};

kj::Own<Piper> pipe(kj::Own<kj::AsyncIoStream> streamA, kj::Own<kj::AsyncIoStream> streamB) {
    return kj::heap<PiperImpl>(std::move(streamA), std::move(streamB));
}

void addrToRaw(kj::Own<kj::NetworkAddress>& address, int port, sockaddr_storage& ss) {
    // a bit ugly hack to convert NetworkAddress to sockaddr
    std::string s = address->toString().cStr();
    int start = 0;
    int length = 0;
    KJ_ASSERT(s.size() > 1);
    void* dst;
    if (s[0] == '[') {
        ss.ss_family = AF_INET6;
        auto it = std::find(s.begin(), s.end(), ']');
        KJ_ASSERT(it != s.end());
        start ++;
        length = it - s.begin() - 1;
        dst = &((sockaddr_in6*)&ss)->sin6_addr;
    } else {
        ss.ss_family = AF_INET;
        auto it = std::find(s.begin(), s.end(), ':');
        KJ_ASSERT(it != s.end());
        length = it - s.begin();
        dst = &((sockaddr_in*)&ss)->sin_addr;
    }

    s = s.substr(start, length);
    int ret = ::inet_pton(ss.ss_family, s.c_str(), dst);
    KJ_REQUIRE(ret == 1, "invalid address");

    if (ss.ss_family == AF_INET6) {
        ((sockaddr_in6*)&ss)->sin6_port = htons((short)port);
    } else {
        ((sockaddr_in*)&ss)->sin_port = htons((short)port);
    }
}

// BoundSocket
class BoundSocketImpl : public BoundSocket {
    kj::LowLevelAsyncIoProvider& provider;
    int port;
    int fd = -1;

public:
    BoundSocketImpl(kj::LowLevelAsyncIoProvider& provider, int fd, int port): provider(provider), port(port), fd(fd) {

    }

    kj::Own<Fd> connectAsFd(kj::Own<kj::NetworkAddress> address, int port) {
        KJ_REQUIRE(fd != -1);

        sockaddr_storage connectAddr;
        socklen_t connectSize = sizeof(connectAddr);
        addrToRaw(address, port, connectAddr);

        int ret;
        do {
            ret = ::connect(fd, (sockaddr*)&connectAddr, connectSize);
        } while(ret < 0 && errno == EINTR);

        if (ret < 0 && errno != EINPROGRESS) {
            KJ_SYSCALL(ret, "connect", address->toString());
        }

        int flag = 1;
        KJ_SYSCALL (setsockopt(fd, SOL_TCP, TCP_NODELAY, &flag, sizeof(flag)));
        auto retfd = Fd::own(fd);
        fd = -1;
        return retfd;
    }

    kj::Promise<kj::Own<kj::AsyncIoStream> > connect(kj::Own<kj::NetworkAddress> address, int port) {
        auto wrapped = provider.wrapConnectingSocketFd(fd);
        fd = -1; // we no longer own the fd
        return wrapped;
    }

    int getPort() {
        return port;
    }

    ~BoundSocketImpl() noexcept {
        if (fd != -1) {
            KJ_ASSERT(fd != 0);
            close(fd);
        }
    }
};

kj::Own<BoundSocket> bindStreamSocket(kj::LowLevelAsyncIoProvider& provider, kj::Own<kj::NetworkAddress> address) {
    sockaddr_storage bindAddr;
    addrToRaw(address, 0, bindAddr);

    int fd;
    KJ_SYSCALL (fd = ::socket(bindAddr.ss_family, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0));
    KJ_REQUIRE (fd > 0, "failed to create socket", errno);

    KJ_SYSCALL (bind(fd, (sockaddr*)&bindAddr, sizeof(bindAddr)));

    sockaddr_storage boundAddr;
    socklen_t boundSize = sizeof(sockaddr_storage);
    int err = ::getsockname(fd, (sockaddr*)&boundAddr, &boundSize);
    if (err != 0) {
        close(fd);
        KJ_REQUIRE(false, "getsockname failed", errno);
    }

    int port;

    if (boundAddr.ss_family == AF_INET) {
        port = htons(((sockaddr_in*)&boundAddr)->sin_port);
    } else if (boundAddr.ss_family == AF_INET6) {
        port = htons(((sockaddr_in6*)&boundAddr)->sin6_port);
    } else {
        KJ_ASSERT(false);
    }

    return kj::heap<BoundSocketImpl>(provider, fd, port);
}

class EmptyOutput : public kj::AsyncOutputStream {
    kj::Promise<void> write(const void* buffer, size_t size) override {
        return kj::READY_NOW; // ?
    }
    kj::Promise<void> write(kj::ArrayPtr<const kj::ArrayPtr<const kj::byte>> pieces) override {
        return kj::READY_NOW;
    }
};

class EmptyInput : public kj::AsyncInputStream {
    kj::Promise<size_t> read(void* buffer, size_t minBytes, size_t maxBytes) override {
        KJ_REQUIRE(minBytes == 0);
        return size_t(0);
    }
    kj::Promise<size_t> tryRead(void* buffer, size_t minBytes, size_t maxBytes) override {
        return size_t(0);
    }
};

class IoStream : public kj::AsyncIoStream {
    kj::Own<kj::AsyncInputStream> input;
    kj::Own<kj::AsyncOutputStream> output;

public:
    IoStream(kj::Own<kj::AsyncInputStream> input,
             kj::Own<kj::AsyncOutputStream> output):
        input(std::move(input)), output(std::move(output)) {}

    kj::Promise<size_t> read(void* buffer, size_t minBytes, size_t maxBytes) override {
        return input->read(buffer, minBytes, maxBytes);
    }
    kj::Promise<size_t> tryRead(void* buffer, size_t minBytes, size_t maxBytes) override {
        return input->tryRead(buffer, minBytes, maxBytes);
    }

    kj::Promise<void> write(const void* buffer, size_t size) override {
        return output->write(buffer, size);
    }
    kj::Promise<void> write(kj::ArrayPtr<const kj::ArrayPtr<const kj::byte>> pieces) override {
        return output->write(pieces);
    }

    void shutdownWrite() override {
        output = kj::heap<EmptyOutput>();
    }
    void abortRead() override {
        input = kj::heap<EmptyInput>();
    }
};

kj::Own<kj::AsyncIoStream> ioStream(kj::Own<kj::AsyncInputStream> input,
                                    kj::Own<kj::AsyncOutputStream> output) {
    return kj::heap<IoStream>(std::move(input), std::move(output));
}

kj::Own<kj::AsyncInputStream> emptyInput() {
    return kj::heap<EmptyInput>();
}

kj::Own<kj::AsyncOutputStream> emptyOutput() {
    return kj::heap<EmptyOutput>();
}

Fd::Fd() {}

Fd::~Fd() {
    if (fd != -1) {
        KJ_ASSERT(fd != 0); // closing stdio is probably an error
        ::close(fd);
    }
}

int Fd::steal() {
    int theFd = fd;
    fd = -1;
    return theFd;
}

kj::Own<Fd> Fd::own(int fd) {
    KJ_ASSERT (fd > 0);
    auto owner = kj::heap<Fd>();
    owner->fd = fd;
    return owner;
}

kj::Own<kj::AsyncInputStream> wrapInputFileFd(kj::AsyncIoProvider& provider, kj::Own<kjfixes::Fd> fd) {
    auto pipeThread = provider.newPipeThread([fdSpec{std::move(fd)}] (kj::AsyncIoProvider& ioProvider, kj::AsyncIoStream& ioStream, kj::WaitScope& waitScope) mutable {
        auto fd = std::move(fdSpec);
        char buf[4096];
        while (true) {
            ssize_t ret;
            KJ_SYSCALL(ret = read(fd->fd, buf, sizeof(buf)));
            if (ret == 0) break;
            ioStream.write(buf, ret).wait(waitScope);
        }
    });

    return kj::heap<AsyncIoStreamProxy<decltype(pipeThread.thread)> >(std::move(pipeThread.pipe), std::move(pipeThread.thread));
}

kj::Promise<kj::Own<Fd> > waitUntilConnected(kj::LowLevelAsyncIoProvider& provider, kj::Own<Fd> fd) {
    int oldFd = fd->fd;
    int newFd = fcntl(oldFd, F_DUPFD_CLOEXEC, 0);
    fd->fd = newFd;
    return provider.wrapConnectingSocketFd(oldFd).then([fdObj{std::move(fd)}](auto socket) mutable {
        // discards socket
        return std::move(fdObj);
    });
}
}
