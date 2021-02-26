#!/bin/bash

if [ ! -e helper/parameters.sh ]; then
        echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
        exit 1
fi

source helper/parameters.sh

# Deactivate VMs

activevms=$(virsh list | grep test-ocp | awk '{print $2}')
for i in $activevms
do
	echo "virsh destroy $i"
	virsh destroy $i
done

# Delete storage volumes

declare -i nvols
pools=$(virsh pool-list --all | grep test-ocp | awk '{print $1}')
for i in $pools
do
	nvols=$(virsh vol-list $i | wc -l)-3
	while :
	do
		if (( nvols < 1 )); then
			break;
		fi
		vol=$(virsh vol-list $i | tail -n 2 | head -n 1 | awk '{ print $1 }')

		echo "virsh vol-delete $vol --pool $i"
		virsh vol-delete $vol --pool $i

		nvols=nvols-1
	done
	echo "virsh pool-destroy $i"
	virsh pool-destroy $i

	echo "virsh pool-delete $i"
	virsh pool-delete $i >/dev/null 2>&1

	echo "virsh pool-undefine $i"
	virsh pool-undefine $i
done

# Delete VM definitions

inactivevms=$(virsh list --all | grep test-ocp | awk '{print $2}')
for i in $inactivevms
do
	echo "virsh undefine $i"
	virsh undefine $i
done

# Delete Virtual Networks

nets=$(virsh net-list --all | grep test-ocp | awk '{print $1}')
for i in $nets
do
	echo "virsh net-destroy $i"
	virsh net-destroy $i

	echo "virsh net-undefine $i"
	virsh net-undefine $i
done

echo "Remove worker node data disk files"

if [ -e $WORKSPACE/.images_path ]; then
	FILES=$(cat $WORKSPACE/.images_path)
	if [ -n "$FILES" ]; then
		rm -rf $FILES/test-ocp*
	fi
fi

