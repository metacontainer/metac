#!/bin/sh
for name in metac; do
    capnp compile metac/${name}.capnp -oc++
done

for name in metac fs blockdevice network stream vm persistence; do
    capnp compile metac/${name}.capnp -onim > metac/${name}_schema.nim
done
