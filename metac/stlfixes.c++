#include "metac/stlfixes.h"
#include <cassert>
#include <stdexcept>

namespace metac {
std::vector<std::string> split(std::string s, char token) {
    std::vector<std::string> ret;
    int pos = 0;
    while (true) {
        int found = s.find(token, pos);
        if (found == -1) {
            ret.push_back(s.substr(pos));
            break;
        } else {
            ret.push_back(s.substr(pos, found - pos - 1));
            pos = found + 1;
        }
    }
    return ret;
}

std::string format(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    std::string result = vformat(fmt, args);
    va_end(args);
    return result;
}

std::string vformat(const char *fmt, va_list args) {
    va_list args_copy;
    va_copy(args_copy, args);
    int required_size = vsnprintf(NULL, 0, fmt, args);

    if (required_size < 0) {
        throw std::invalid_argument("vsnprintf failed");
    }

    std::vector<char> buffer (required_size + 1);
    int actual_size = vsnprintf(buffer.data(), required_size + 1, fmt, args_copy);
    assert(actual_size == required_size);
    return std::string(buffer.data(), actual_size);
}
}
