#!/bin/bash

addr=fdca:ddf9:5703::1

sudo mkdir -p /run/metac/$addr

if [ ! -e /sys/class/net/metac1 ]; then
    sudo ip link add metac1 type bridge
    sudo ip addr add dev metac1 $addr
    sudo ip link set dev metac1 up
fi

sudo rundev dev -- sh -c "
rundev add bridge -- ./build/metac-bridge $addr
sleep 0.5
"
