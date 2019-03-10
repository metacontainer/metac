import requests
from . import unix_http
from mypy_extensions import TypedDict
from typing import TypeVar, List, Generic, NamedTuple, no_type_check, Union, Iterator
from enum import Enum

T = TypeVar('T')
R = TypeVar('R')

def deserialize_json(ctx, data, typ):
    if typ in (int, str, float, bool):
        return typ(data)
    elif getattr(typ, '__origin__', None) == List:
        assert type(data) == list
        sub, = typ.__args__
        return [ deserialize_json(ctx, item, sub) for item in data ]
    elif getattr(typ, '__origin__', None) == Union:
        if len(typ.__args__) != 2 or type(None) not in typ.__args__:
            raise Exception("among Union types, only Optional is supported")

        orig_type = list(set(typ.__args__) - set([type(None)]))[0]
        if data is None: return None

        return deserialize_json(ctx, data, orig_type)
    elif hasattr(typ, '_field_types'): # NamedTuple
        vals = {}
        for k, ktyp in typ._field_types.items():
            vals[k] = deserialize_json(ctx, data[k], ktyp)
        return typ(**vals)
    elif hasattr(typ, '_deserialize_json'):
        return typ._deserialize_json(ctx, data)
    elif typ.__base__ == Enum:
        if data not in typ.__members__:
            raise Exception('invalid enum %s value: %r' % (typ.__name__, data))

        return getattr(typ, data)
    elif typ == type(None):
        return None
    else:
        raise Exception('unsupported type %s' % typ)

def serialize_json(data):
    typ = type(data)
    if typ in (int, str, float, bool) or data is None:
        return data
    elif typ.__base__ is tuple:
        res = {}
        for k, v in zip(typ._field_types, data):
            res[k] = serialize_json(v)
        return res
    elif typ is list:
        return [ serialize_json(v) for v in data ]
    elif hasattr(typ, '_serialize_json'):
        return data._serialize_json()
    elif typ.__base__ is Enum:
        return data.name
    else:
        raise Exception('unsupported type %s (base = %s)' % (typ, typ.__base__))

def get_session():
    return unix_http.Session()

class Ctx(NamedTuple):
    base_rpath: str

class MetacException(Exception): pass

def raise_for_status(resp):
    if resp.status_code == 500 and resp.headers.get('content-type') == 'application/json':
        raise MetacException(resp.json().get('message'))
    resp.raise_for_status()

def deserialize_resp(ref, resp, T):
    raise_for_status(resp)
    ctx = Ctx(ref.rpath)
    return deserialize_json(ctx, resp.json(), T)

class Ref:
    def __init__(self, rpath):
        self.rpath = rpath

    @classmethod
    def _deserialize_json(cls, ctx, data):
        if list(data.keys()) != ['_ref']:
            raise Exception('invalid ref')

        assert ctx.base_rpath.endswith('/')
        rpath = ctx.base_rpath + data['_ref']
        if not rpath.endswith('/'): rpath += '/'
        return cls(rpath)

    def _serialize_json(self):
        return {'_ref': self.rpath}

    @property
    def url(self):
        return 'metac:/' + self.rpath

    def __repr__(self):
        return '%s(%r)' % (type(self).__name__, self.rpath)

class GetMixin(Generic[T]):
    def get(self) -> T:
        return deserialize_resp(self, get_session().get(self.url), self.value_type) # type: ignore

class UpdateMixin(Generic[T]):
    def update(self, v: T):
        deserialize_resp(
            self,
            get_session().put(self.url, json=serialize_json(v)), # type: ignore
            None
        )

class CollectionMixin(Generic[T, R]):
    def __getitem__(self, id):
        assert '/' not in id
        return self.ref_type(self.rpath + id + '/')

    def values(self) -> List[R]:
        return deserialize_resp(self, get_session().get(self.url), List[self.ref_type]) # type: ignore

    def __iter__(self) -> Iterator[R]:
        return iter(self.values())

    def create(self, v: T) -> R:
        return deserialize_resp(
            self,
            get_session().post(self.url, json=serialize_json(v)), # type: ignore
            self.ref_type # type: ignore
        )

class DeleteMixin:
    def delete(self):
        deserialize_resp(self, get_session().delete(self.url), None)

class Metadata(NamedTuple):
    name: str
