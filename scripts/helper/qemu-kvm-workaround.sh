#!/bin/bash

set -e

if [ "$( whoami )" != "root" ]; then
    echo "This script must be invoked by root"
    exit 1
fi

arg1=$1

if [ -z "$arg1" ]; then
	echo "Usage $0 { --install | --uninstall }"
	exit 1
fi

if [ ! -e helper/parameters.sh ]; then
        echo "ERROR: This script should be invoked from the directory ocs-upi-kvm/scripts"
        exit 1
fi

if [ "$arg1" == "--install" ]; then
	if [ ! -e /usr/libexec/qemu-kvm.bin ]; then
		mv /usr/libexec/qemu-kvm /usr/libexec/qemu-kvm.bin
	fi
	cp -f ../files/qemu-kvm /usr/libexec/qemu-kvm
	restorecon -vR /usr/libexec
elif [ "$arg1" == "--uninstall" ]; then
	if [ -e /usr/libexec/qemu-kvm.bin ]; then
		mv /usr/libexec/qemu-kvm.bin /usr/libexec/qemu-kvm
	fi
	restorecon -vR /usr/libexec
else
	echo "Usage $0 { --install | --uninstall }"
	exit 1
fi
