#include "metac/metac.h"
#include "metac/stream.h"
#include "metac/kjfixes.h"

int main() {
    kj::_::Debug::setLogLevel(kj::_::Debug::Severity::INFO);

    auto instance = metac::createInstance("10.234.0.1");
    auto& w = instance->getWaitScope();

    auto localAddr = instance->getIoProvider().getNetwork().parseAddress("localhost:5000").wait(w);
    auto wrapped = metac::wrapStream(instance, localAddr->connect().wait(w));
    auto unwrapped = metac::unwrapStream(instance, wrapped).wait(w);

    char buffer[1024];
    memset(buffer, 0, sizeof(buffer));

    unwrapped->write("hello\n", 6).wait(w);

    unwrapped->read(buffer, 1, sizeof(buffer)).then([&] (size_t size) {
        KJ_LOG(INFO, "read", size, std::string(buffer, size));
    }).wait(instance->getWaitScope());

    kj::NEVER_DONE.wait(instance->getWaitScope());
}
