#!/bin/bash
tar cf node_modules.tar node_modules
xz node_modules.tar
cdn-in node_modules.tar
