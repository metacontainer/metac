#include "metac/stlfixes.h"

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
}
