#!/bin/sh
for name in metac stream network fs vm blockdevice; do
    capnp compile metac/${name}.capnp -oc++
done
