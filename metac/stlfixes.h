#ifndef _METAC_STL_FIXES_H
#define _METAC_STL_FIXES_H
#include <utility>
#include <memory>
#include <string>
#include <vector>

namespace metac {

template <typename T>
struct hash {
    std::size_t operator()(const T& x) const {
        return std::hash<T>()(x);
    }
};

template <typename A, typename B>
struct hash<std::pair<A, B> > {
    std::size_t operator()(const std::pair<A, B> &x) const {
        return (hash<A>()(x.first) * 533306145) ^ hash<B>()(x.second);
    }
};

template <typename T>
using Rc = std::shared_ptr<T>;

std::vector<std::string> split(std::string s, char token);
}

#endif
