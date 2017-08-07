#!/bin/sh
set -ex

PREFIX="$1"

if [ "PREFIX" = "" ]; then
    dir=/etc/systemd/system
else
    dir=$PREFIX/lib/systemd/system
fi

mkdir -p $dir
cp metac/metac.target $dir/
cp metac/bridge.service $dir/metac-bridge.service

pkgs="persistence vm fs network computevm desktop"
for name in $pkgs; do
    cat <<EOF > $dir/metac-$name.service
[Unit]
Description=MetaContainer $name service
After=metac-bridge.service
PartOf=metac.target

[Service]
ExecStart=/usr/bin/metac $name-service
Type=notify
Restart=on-failure
EnvironmentFile=/etc/default/metac

[Install]
WantedBy=metac.target

EOF
done

if [ "PREFIX" = "" ]; then
    systemctl enable metac.target
    systemctl enable metac-bridge
    for name in $pkgs; do
        systemctl enable metac-$name
    done
    systemctl daemon-reload
fi
