#include <kj/async-io.h>
#include <memory>

template <typename T>
class AsyncIoStreamProxy : public kj::AsyncIoStream {
    // proxy that additionally keeps an object alive
    kj::Own<kj::AsyncIoStream> stream;
    T holder;
public:
    AsyncIoStreamProxy(kj::Own<kj::AsyncIoStream> stream, T holder):
        stream(std::move(stream)), holder(std::move(holder)) {}

    kj::Promise<size_t> read(void* buffer, size_t minBytes, size_t maxBytes) {
        return stream->read(buffer, minBytes, maxBytes);
    }
    kj::Promise<size_t> tryRead(void* buffer, size_t minBytes, size_t maxBytes) {
        return stream->tryRead(buffer, minBytes, maxBytes);
    }
    kj::Promise<void> write(const void* buffer, size_t size) {
        return stream->write(buffer, size);
    }
    kj::Promise<void> write(kj::ArrayPtr<const kj::ArrayPtr<const kj::byte>> pieces) {
        return stream->write(pieces);
    }
    void shutdownWrite() {
        stream->shutdownWrite();
    }
    void abortRead() {
        stream->abortRead();
    }
    void getsockopt(int level, int option, void* value, uint* length) {
        stream->getsockopt(level, option, value, length);
    }
    void setsockopt(int level, int option, const void* value, uint length) {
        stream->setsockopt(level, option, value, length);
    }
    void getsockname(struct sockaddr* addr, uint* length) {
        stream->getsockname(addr, length);
    }
    void getpeername(struct sockaddr* addr, uint* length) {
        stream->getpeername(addr, length);
    }
};
