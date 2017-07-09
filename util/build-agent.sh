#!/bin/bash
# Build computevm agent
set -e

kernel=$(nix-build metac.nix -A vmKernel)
musl=$(nix-build '<nixpkgs>' -A musl)
linuxHeaders=$(nix-build '<nixpkgs>' -A linuxHeaders)

ln -sf $kernel/bzImage build/vmlinuz

nim c -d:musl \
    --out:build/compute_agent \
    --passc:"-I$linuxHeaders/include" \
    --gcc.linkerexe:"$musl/bin/musl-gcc" \
    --gcc.exe:"$musl/bin/musl-gcc" \
    metac/compute_agent.nim
mkdir -p build/initrd/bin
cp build/compute_agent build/initrd/init
cp /bin/busybox build/initrd/bin/busybox
for name in sh mount ifconfig ip; do
    ln -sf /bin/busybox build/initrd/bin/$name
done
(cd build/initrd && find ./ | cpio -H newc -o > ../initrd.cpio)
