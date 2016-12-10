#!/bin/sh
for name in metac; do
    capnp compile metac/${name}.capnp -oc++
done
