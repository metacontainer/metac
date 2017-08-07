#!/bin/sh
ln -sf $(nix-build metac.nix -A sftpServer)/bin/sftp-server build/metac-sftp-server
ln -sf $(nix-build metac.nix -A sshfs)/bin/sshfs build/metac-sshfs

tigervnc=$(nix-build metac.nix -A tigervnc)
for i in vncviewer x0vncserver; do
    ln -sf $tigervnc/bin/$i build/$i
done
