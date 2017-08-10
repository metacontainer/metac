#!/bin/sh
for name in metac; do
    capnp compile metac/${name}.capnp -oc++
done

for name in metac fs network stream vm persistence compute usb sound computevm_internal desktop; do
    capnp compile metac/${name}.capnp -onim > metac/${name}_schema.nim
done
