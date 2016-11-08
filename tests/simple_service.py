import sys, os, time
sys.path.append(os.path.dirname(os.path.dirname(__file__)))
import capnp
import metac_capnp

client = capnp.TwoPartyClient('10.234.0.1:901').bootstrap().cast_as(metac_capnp.Node)
print(client.address().wait())

try:
    print(client.getService(metac_capnp.ServiceId.new_message(named='test')).wait())
except Exception as err:
    print(err)

class MyService(metac_capnp.Service.Server):
    pass

r = client.registerAnonymousService(MyService()).wait()
my_id = r.id.as_builder()
print(my_id)
my_proxied = client.getService(my_id).wait()
