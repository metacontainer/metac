#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <assert.h>
#include <fcntl.h>

// This library is intended to be LD_PRELOADed. It catches all attempt to bind and connect to port 1 and redirect the socket to BIND_FD and CONNECT_FD respectively.

typedef int (*bind_fun)(int fd, const struct sockaddr *addr, socklen_t addrlen);

int bind(int fd, const struct sockaddr *addr, socklen_t addrlen) {
    int port = 0;
    if (addr->sa_family == AF_INET) {
        port = ((struct sockaddr_in*)addr)->sin_port;
    } else if (addr->sa_family == AF_INET6) {
        port = ((struct sockaddr_in6*)addr)->sin6_port;
    }
    if (port == 0x0100) {
        static int bound = 0;
        if (bound) {
            errno = -ENOTSUP;
            return 0;
        }
        bound = 1;

        const char* env = getenv("BIND_FD");
        if (env == NULL) {
            errno = ENODEV;
            return -1;
        }
        errno = 0;
        int new_fd = strtol(env, NULL, 10);
        if (errno != 0)
            return -1;

        int old_flags = fcntl(fd, F_GETFL);
        int old_fd_flags = fcntl(fd, F_GETFD);
        dup2(new_fd, fd);
        fcntl(fd, F_SETFL, old_flags);
        fcntl(fd, F_SETFD, old_fd_flags);

        return 0;
    }

    bind_fun next_bind = (bind_fun) dlsym(RTLD_NEXT, "bind");
    assert (next_bind != NULL);

    return next_bind(fd, addr, addrlen);
}

int connect(int fd, const struct sockaddr *addr, socklen_t addrlen) {
    int port = 0;
    if (addr->sa_family == AF_INET) {
        port = ((struct sockaddr_in*)addr)->sin_port;
    } else if (addr->sa_family == AF_INET6) {
        port = ((struct sockaddr_in6*)addr)->sin6_port;
    }

    if (port == 0x0100 || port == 0x0d17) { // 1 or 5901
        const char* env = getenv("CONNECT_FD");
        if (env == NULL) {
            errno = ENODEV;
            return -1;
        }
        errno = 0;
        int new_fd = strtol(env, NULL, 10);
        if (errno != 0)
            return -1;

        int old_flags = fcntl(fd, F_GETFL);
        int old_fd_flags = fcntl(fd, F_GETFD);
        dup2(new_fd, fd);
        fcntl(fd, F_SETFL, old_flags);
        fcntl(fd, F_SETFD, old_fd_flags);

        return 0;
    }

    bind_fun next_connect = (bind_fun) dlsym(RTLD_NEXT, "connect");
    assert (next_connect != NULL);

    return next_connect(fd, addr, addrlen);
}
