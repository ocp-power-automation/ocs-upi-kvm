#!/bin/bash

# Create and attach a data disk to each worker node

# One can attach a disk partition or a qcow2 file.  The qcow2 method is
# the default, which can be overridden by specifying a comma separated list
# of disk partitions via the environment variable DATA_DISK_LIST.

set -e

if [ ! -e helper/parameters.sh ]; then
        echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
        exit 1
fi

source helper/parameters.sh

if [ -n "$DATA_DISK_ARRAY" ]; then

	for (( i=0; i<$WORKERS; i++ ))
	do
		pname=${DATA_DISK_ARRAY[$i]}
		echo "Attaching /dev/$pname to test-ocp$OCP_VERSION-worker-$i"
 		virsh list | grep worker-$i | tail -n 1 | awk -v var="$i" '{system("virsh attach-disk " $2 " --source /dev/$pname --target vdc --persistent")}'
	done

	exit 
fi

# Remember where files were created for virsh_cleanup.sh

echo "$IMAGES_PATH" > ~/.images_path

rm -f $IMAGES_PATH/test-ocp$OCP_VERSION/*.data

if [ "$DATA_DISK_SIZE" -le "0" ]; then
	echo "No data disks will be created"
	exit
fi

for (( i=0; i<$WORKERS; i++ ))
do
	echo "Creating data disk $IMAGES_PATH/test-ocp$OCP_VERSION/disk-worker${i}.data ${DATA_DISK_SIZE}G"

	qemu-img create -f raw $IMAGES_PATH/test-ocp$OCP_VERSION/disk-worker${i}.data ${DATA_DISK_SIZE}G

	echo "Attaching data disk to test-ocp$OCP_VERSION-worker-$i"

 	virsh list | grep worker-$i | tail -n 1 | awk -v var="$i" '{system("virsh attach-disk " $2 " --source $IMAGES_PATH/test-ocp$OCP_VERSION/disk-worker" var ".data --target vdc --persistent")}'
done

