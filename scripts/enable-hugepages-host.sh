#!/bin/bash

if [ ! -e helper/parameters.sh ]; then
        echo "ERROR: This script should be invoked from the directory ocs-upi-kvm/scripts"
        exit 1
fi

set -e

source helper/parameters.sh

if [ "$PLATFORM" != kvm ]; then
	echo "ERROR: The enable-hugepages-host.sh script is not implemented on $PLATFORM"
	exit 1
fi

helper/kvm/enable-hugepages.sh
