#!/bin/sh
ln -sf $(nix-build metac.nix -A sftpServer)/bin/sftp-server build/metac-sftp-server
ln -sf $(nix-build metac.nix -A sshfs)/bin/sshfs build/metac-sshfs
