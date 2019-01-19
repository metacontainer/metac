#!/bin/bash
rm -r helpers
mkdir helpers
for i in $(nix-build -A tigervnc -A sftpServer -A sshfsFuse); do
    for j in $i/bin/*; do
        ln -s $j helpers
    done
done
