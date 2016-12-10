#!/bin/bash
sudo rundev dev -- sh -c '
rundev add bridge -- ./build/metac-bridge 10.234.0.1
rundev add vm -- ./build/metac-vm 10.234.0.1
'
