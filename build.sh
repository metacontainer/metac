#!/bin/sh
for name in metac stream network fs; do
    capnp compile metac/${name}.capnp -oc++
done
