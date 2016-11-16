from typing import Tuple
from metac.metac import load, Instance

import socket, threading, logging, sys

stream_capnp = load('metac/stream.capnp')
metac_capnp = load('metac/metac.capnp')

def unwrap(instance: Instance, stream) -> Tuple[socket.socket, object]:
    # Converts `stream` into a socket. Returns pair (socket, holder).
    sock = socket.socket()
    sock.bind((instance.address, 0))
    port = sock.getsockaddr()[1] # type: ignore

    resp = stream.tcpListen(remote=metac_capnp.NodeAddress.new_message(ip=instance.address),
                            port=port).wait()
    address, port, holder = resp.local.ip, resp.port, resp.holder
    sock.connect((address, port))

    return sock, holder

class Holder(metac_capnp.Holder.Server):
    def __init__(self, obj):
        self.obj = obj

class WrappedStream(stream_capnp.Stream.Server):
    def __init__(self, instance, callback):
        self.callback = callback
        self.instance = instance
        self.remote = None
        self.port = None

    def handle(self, sock):
        while True:
            client, addr = sock.accept()
            if addr != (self.remote, self.port):
                logging.warn('connection from invalid peer: %s (required %s)', addr, (self.remote, self.port))
            else:
                break

            del client

        other = client.makefile('rwb')
        self.callback(other)

    def tcpListen(self, remote, port, **kwargs):
        self.remote = remote.ip
        self.port = port

        sock = socket.socket()
        sock.bind((self.instance.address, 0))
        sock.listen(5)

        threading.Thread(target=self.handle, args=[sock]).start()

        return (metac_capnp.NodeAddress.new_message(ip=self.instance.address), sock.getsockname()[1], Holder(self))

def wrap(instance: Instance, callback):
    # Only for testing.
    return WrappedStream(instance, callback)

def debug_print_stream(instance: Instance, prefix: str):
    # Only for testing.
    def callback(stream):
        while True:
            line = stream.readline()
            if not line:
                break

            sys.stdout.buffer.write(prefix.encode() + line)

    return wrap(instance, callback)
