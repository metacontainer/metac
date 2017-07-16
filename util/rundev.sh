#!/bin/bash

addr="$1"
if [ "$addr" = "" ]; then
    addr=fdca:ddf9:5703::1
fi
METAC_ADDRESS=$addr

sudo mkdir -p /run/metac/$addr

if [ ! -e /sys/class/net/metac1 ]; then
    sudo ip link add metac1 type bridge
    sudo ip addr add dev metac1 $addr
    sudo ip link set dev metac1 up
    sleep 1 # wait for DAD
fi

sudo rundev dev --env PATH=$PATH --env=METAC_ADDRESS=$addr -- sh -c "
rundev add bridge -- metac bridge
sleep 0.1
rundev add persistence-service -- metac persistence-service
rundev add fs-service -- metac fs-service
rundev add vm-service -- metac vm-service
rundev add network-service -- metac network-service
rundev add sound-service -- metac sound-service
rundev add computevm-service -- metac computevm-service
"
