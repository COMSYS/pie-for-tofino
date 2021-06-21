#!/bin/bash

DIRECTORY=$(cd `dirname $0` && pwd)
export PATH=$SDE_INSTALL/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/lib:$SDE_INSTALL/lib:$LD_LIBRARY_PATH

sudo -E env "PATH=$PATH" "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" "$DIRECTORY/run_controlplane_pie" -p pie_controlplane$1 $1
