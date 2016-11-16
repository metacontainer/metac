#include "metac/subprocess.h"
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <kj/debug.h>
#include <unistd.h>
#include <algorithm>
#include <fcntl.h>

namespace metac {
namespace subprocess {

class ProcessImpl : public Process {
    int pid = -1;

public:
    ~ProcessImpl() {
        if (pid != -1) kill();
    }

    ProcessImpl(int pid): pid(pid) {}

    void detach() {
        KJ_REQUIRE(::waitpid(pid, NULL, WNOHANG) > 0);
        pid = -1;
    }

    void kill() {
        KJ_REQUIRE (pid != -1);
        ::kill(pid, SIGKILL);
        pid = -1;
    }

    int getPid() {
        return pid;
    }
};

kj::Own<Process> ProcessBuilder::start() {
    int ret = fork();
    KJ_REQUIRE (ret >= 0, "fork failed");

    std::vector<int> originalFdFlags;
    for (int fd : keepFds) {
        int flags = fcntl(fd, F_GETFD);
        originalFdFlags.push_back(flags);
        fcntl(fd, F_SETFD, flags & (~FD_CLOEXEC));
    }

    if (ret == 0) {
        // child
        for (int i=3; i < 1024; i ++) {
            if (std::find(keepFds.begin(), keepFds.end(), i) == keepFds.end()) {
                close(i);
            }
        }

        std::vector<const char*> cargs;
        for (const std::string& arg : args)
            cargs.push_back(arg.c_str());
        cargs.push_back(NULL);

        ::execvp(cargs[0], (char**)cargs.data());
        perror("execvp failed;");
        _exit(1);
    }
    // parent

    for (int i=0; i < keepFds.size(); i ++) {
        int fd = keepFds[i];
        fcntl(fd, F_SETFD, originalFdFlags[i]);
    }

    return kj::heap<ProcessImpl>(ret);
}

}
}
