#!/bin/bash
rm -r helpers
mkdir helpers

ln -s $(nix-build -A agent.vmKernel --no-out-link)/bzImage helpers/agent-vmlinuz

for i in $(nix-build -A tigervnc -A sftpServer -A sshfsFuse -A qemu --no-out-link); do
    for j in $i/bin/*; do
        ln -s $j helpers
    done
done
