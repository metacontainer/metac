#include "ostools.h"
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <random>

namespace metac {
bool fileExists(std::string name) {
    struct stat buf;
    return lstat(name.c_str(), &buf) == 0;
}

void createDir(std::string name) {
    mkdir(name.c_str(), 0700);
}

void unlink(std::string path) {
    ::unlink(path.c_str());
}

std::string randomHexString(int length) {
    std::uniform_int_distribution<int> dist(0, 16);
    std::random_device urandom("/dev/urandom");
    std::string s;

    for (int i=0; i < length; i ++) {
        int v = dist(urandom);
        s.push_back(v < 10 ? v + '0' : v + 'a' - 10);
    }

    return s;
}

}
