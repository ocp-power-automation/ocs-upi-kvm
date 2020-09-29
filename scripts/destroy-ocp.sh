#!/bin/bash

user=$(whoami)
if [ "$user" != root ]; then
        echo "This script must be invoked as root"
        exit 1
fi

set -e

if [ ! -e helper/virsh-cleanup.sh ]; then
        echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
        exit 1
fi

helper/virsh-cleanup.sh
