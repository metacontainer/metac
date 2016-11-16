#ifndef METAC_SUBPROCESS_H
#define METAC_SUBPROCESS_H
#include <kj/async-io.h>
#include <vector>
#include <string>
// Library for spawning subprocesses

namespace metac {
namespace subprocess {

class Process {
public:
    virtual ~Process() {};
    virtual void kill() = 0;

    virtual int getPid() = 0;
};

struct ProcessBuilder {
    std::vector<std::string> args;
    std::vector<int> keepFds;

    ProcessBuilder(std::vector<std::string> args): args(args) {}

    kj::Own<Process> start();
};

}
}

#endif
