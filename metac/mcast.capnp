@0xe669517eda764a9f;

using Cxx = import "c++.capnp";
$Cxx.namespace("metac::mcast");

# Metac mcast is a partition tolerant highly-available metadata store.
# It doesn't provide much consistency, except in optimistic case when everyone is in single connected component.
#
# It is used to create persistent capabilities that don't rely on a single node being up and to manage metadata of distributed networks (e.g. distributed ethernet switch).
