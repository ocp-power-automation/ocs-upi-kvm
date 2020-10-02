#!/bin/bash

set -e

if [ ! -e helper/virsh-cleanup.sh ]; then
        echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
        exit 1
fi

sudo -s helper/virsh-cleanup.sh
