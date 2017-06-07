#!/bin/sh
# Build computevm agent
set -e
if [ ! -e build/vmlinuz ]; then
    wget https://cdn.atomshare.net/8d99742552a6b2730aaccd15df10ca5b3e5281d5/vmlinuz-4.4.20 -O build/vmlinuz
fi

nim c --out:build/compute_agent metac/compute_agent.nim
mkdir -p build/initrd/bin
cp build/compute_agent build/initrd/init
cp /bin/busybox build/initrd/bin/busybox
for name in sh mount ifconfig ip; do
    ln -sf /bin/busybox build/initrd/bin/$name
done
(cd build/initrd && find ./ | cpio -H newc -o > ../initrd.cpio)
