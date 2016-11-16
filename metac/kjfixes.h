#ifndef _METAC_KJFIXES_H
#define _METAC_KJFIXES_H
#include <kj/async-io.h>
#include <kj/debug.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <string>
#include <vector>
#include "metac/ostools.h"

namespace kjfixes {
std::pair<std::string, int> getPeerName(kj::Own<kj::AsyncIoStream>& sock);
// Get IP address and port of the remote peer of socket `sock`.

class Piper {
public:
    virtual ~Piper() {}
};

kj::Own<Piper> pipe(kj::Own<kj::AsyncIoStream> streamA, kj::Own<kj::AsyncIoStream> streamB);
// Pipe all data between streams `streamA` and `streamB`.

class Fd {
public:
    ~Fd();
    Fd();

    int fd = -1;
    // The managed file descriptor.

    int steal();
    // Stop owning the file descriptor and return it.

    static kj::Own<Fd> own(int fd);
    // Construct Fd instance
};

class BoundSocket {
public:
    virtual kj::Promise<kj::Own<kj::AsyncIoStream> > connect(kj::Own<kj::NetworkAddress> address, int port) = 0;
    virtual kj::Own<Fd> connectAsFd(kj::Own<kj::NetworkAddress> address, int port) = 0;
    virtual int getPort() = 0;
    virtual ~BoundSocket() {}
};
kj::Own<BoundSocket> bindStreamSocket(kj::LowLevelAsyncIoProvider& provider, kj::Own<kj::NetworkAddress> address);

kj::Own<kj::AsyncIoStream> ioStream(kj::Own<kj::AsyncInputStream> input,
                                    kj::Own<kj::AsyncOutputStream> output);


kj::Own<kj::AsyncInputStream> emptyInput();
kj::Own<kj::AsyncOutputStream> emptyOutput();

kj::Own<kj::AsyncInputStream> wrapInputFileFd(kj::AsyncIoProvider& provider, kj::Own<Fd> fd);
// Wrap file descriptor representing a normal file.

kj::Promise<kj::Own<Fd> > waitUntilConnected(kj::LowLevelAsyncIoProvider& provider, kj::Own<Fd> fd);
}

#endif
