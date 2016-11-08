#ifndef _METAC_STREAM_H
#define _METAC_STREAM_H
#include "metac/metac.h"
#include "metac/stream.capnp.h"
#include "metac/stlfixes.h"
#include <kj/async-io.h>
#include <functional>

namespace metac {
using StreamProvider = std::function<kj::Promise<kj::Own<kj::AsyncIoStream> >() >;
Stream::Client wrapStream(Rc<Instance> instance, kj::Own<kj::AsyncIoStream> stream);
Stream::Client wrapStream(Rc<Instance> instance, StreamProvider stream);
kj::Promise<kj::Own<kj::AsyncIoStream> > unwrapStream(Rc<Instance> instance, Stream::Client stream);
}

#endif
