import capnp
import os, threading, socket, binascii, traceback

def load(name):
    return capnp.load(name, imports=['/usr/local/include'])

metac_capnp = load('metac/metac.capnp')

class Instance:
    '''
    Mirrors C++ metac::Instance.
    '''
    def __init__(self, address: str) -> None:
        self.address = address

        if os.getuid() == 0:
            self.client = capnp.TwoPartyClient('unix:/run/metac/' + address + '/socket')
            self.node_admin = self.client.bootstrap().cast_as(metac_capnp.NodeAdmin)
            self.node = self.node_admin.getUnprivilegedNode().wait()
        else:
            self.client = capnp.TwoPartyClient(address + ':901')
            self.node_admin = None
            self.node = self.client.bootstrap().cast_as(metac_capnp.Node)

        # for CastToLocal
        self.local_objects = {}

    def wait(self):
        self.client.on_disconnect().wait()

    def get_service(self, name, as_type):
        metac_capnp.ServiceId.new_message(named='test')

    def threaded_object(self, func, interface):
        a, b = socket.socketpair()

        def run_server():
            capnp.create_event_loop()
            server = capnp.TwoPartyServer(b, bootstrap=func())
            server.on_disconnect().wait()

        threading.Thread(target=run_server).start()
        
        client = capnp.TwoPartyClient(a).bootstrap().cast_as(interface)
        return client

    def cast_to_local(self, obj, type):
        id = binascii.hexlify(os.urandom(32))
        self.local_objects[id] = [None, type]

        promise = obj.cast_as(metac_capnp.CastToLocal).registerLocal(id)

        def then():
            val = self.local_objects[id][0]
            if val is None:
                raise Exception('value not returned')
            del self.local_objects[id]
            return val

        return promise.then(then)

class CastToLocal(metac_capnp.CastToLocal.Server):
    def registerLocal(self, id):
        t = self.instance[id]
        if not isinstance(self, t[1]):
            raise Exception('bad ID')
        t[1] = self
