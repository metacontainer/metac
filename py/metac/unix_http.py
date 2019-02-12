# Based on code from https://github.com/msabramo/requests-unixsocket/blob/master/requests_unixsocket/adapters.py
# License: Apache License 2.0
# Contributors: https://github.com/msabramo/requests-unixsocket/graphs/contributors

import socket, requests, os

from requests.adapters import HTTPAdapter
from requests.compat import urlparse, unquote

try:
    import http.client as httplib
except ImportError:
    import httplib

try:
    from requests.packages import urllib3
except ImportError:
    import urllib3

def get_socket_path(name):
    assert '/' not in name
    if os.getuid() == 0:
        return "/run/metac/service-%s.socket" % name
    else:
        return "%s/metac/run/service-%s.socket" % (
            os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')),
            name
        )

class MetacHTTPConnection(httplib.HTTPConnection):
    def __init__(self, unix_socket_url, timeout=60):
        super().__init__('localhost', timeout=timeout)
        self.unix_socket_url = unix_socket_url
        self.sock = None

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        socket_path = get_socket_path(urlparse(self.unix_socket_url).netloc)
        sock.connect(socket_path)
        self.sock = sock

class MetacHTTPConnectionPool(urllib3.connectionpool.HTTPConnectionPool):
    def __init__(self, socket_path, timeout=60):
        super().__init__('localhost', timeout=timeout)
        self.socket_path = socket_path
        self.timeout = timeout

    def _new_conn(self):
        return MetacHTTPConnection(self.socket_path, self.timeout)

class MetacAdapter(HTTPAdapter):
    def get_connection(self, url, proxies=None):
        return MetacHTTPConnectionPool(url)

    def request_url(self, request, proxies):
        return request.path_url

    def close(self):
        self.pools.clear()

class Session(requests.Session):
    def __init__(self, *args, **kwargs):
        super(Session, self).__init__(*args, **kwargs)
        self.mount('metac', MetacAdapter())
