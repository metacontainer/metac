#include "metac/fs.h"
#include "metac/metac.h"
#include "metac/stlfixes.h"
#include "metac/kjfixes.h"
#include "metac/ostools.h"
#include "metac/stream.h"
#include <string>
#include <kj/debug.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

namespace metac {
namespace fs {

std::string safeJoin(std::string base, std::string child) {
    // Safely join `base` and `child` paths - it guaranteed that the resulting
    // path will be inside `base`.
    // Here we asume that the filesystem is sane (e.g. probably not Mac OSX)
    KJ_REQUIRE (split(child, '/').size() + split(base, '/').size() < 40);
    for (auto item : split(child, '/')) {
        KJ_REQUIRE(item != ".." && item != "." && item != "-");
        base += "/" + item;
    }
    return base;
}

using kjfixes::Fd;

kj::Own<Fd> openAt(std::string path, int finalFlags=O_DIRECTORY) {
    // Open file at `path` without following symlinks.
    int fd;
    KJ_SYSCALL(fd = ::open("/", O_DIRECTORY | O_NOFOLLOW));
    kj::Own<Fd> currFd = Fd::own(fd);
    auto items = split(path, '/');
    for (unsigned i=0; i < items.size(); i ++) {
        int flags = i == (items.size() - 1) ? finalFlags : O_DIRECTORY;
        flags |= O_NOFOLLOW;
        KJ_SYSCALL(fd = ::openat(currFd->fd, items[i].c_str(), flags));
        currFd = Fd::own(fd);
    }
    return currFd;
}

class LocalFileImpl : public File::Server {
    Rc<Instance> instance;
    std::string path;
public:
    LocalFileImpl(Rc<Instance> instance, std::string path): instance(instance), path(path) {}

    kj::Promise<void> openAsStream(OpenAsStreamContext context) override {
        kj::Own<Fd> fd = openAt(path, O_RDONLY);
        auto wrapped = kjfixes::wrapInputFileFd(instance->getIoProvider(), std::move(fd));
        auto ioStream = kjfixes::ioStream(std::move(wrapped), kjfixes::emptyOutput());
        context.getResults().setStream(wrapStream(instance, std::move(ioStream)));
        return kj::READY_NOW;
    }
};

class LocalFilesystemImpl : public Filesystem::Server {
    Rc<Instance> instance;
    std::string path;
public:
    LocalFilesystemImpl(Rc<Instance> instance, std::string path): instance(instance), path(path) {}

    kj::Promise<void> getSubtree(GetSubtreeContext context) {
        std::string newPath = safeJoin(path, context.getParams().getName());
        context.getResults().setFs(kj::heap<LocalFilesystemImpl>(instance, newPath));
        return kj::READY_NOW;
    }

    kj::Promise<void> getFile(GetFileContext context) {
        std::string newPath = safeJoin(path, context.getParams().getName());
        context.getResults().setFile(kj::heap<LocalFileImpl>(instance, newPath));
        return kj::READY_NOW;
    }

};

Filesystem::Client getLocalFilesystem(Rc<Instance> instance) {
    return kj::heap<LocalFilesystemImpl>(instance, "/");
}

}
}
