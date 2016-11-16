#ifndef _METAC_STL_FIXES_H
#define _METAC_STL_FIXES_H
#include <utility>
#include <memory>
#include <string>
#include <vector>
#include <cstdarg>
#include <ostream>

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

template <typename T>
std::vector<T>& operator+=(std::vector<T>& a, std::vector<T> b) {
    a.insert(a.end(), b.begin(), b.end());
    return a;
}

std::string format(const char* format, ...);
std::string vformat(const char *fmt, va_list args);

template <typename T>
std::ostream& operator<<(std::ostream& s, const std::vector<T>& t) {
    s << "{";
    for (const T& item: t) {
        s << item << ", ";
    }
    s << "}";
    return s;
}

}

#endif
