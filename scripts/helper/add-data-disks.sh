#!/bin/bash

# Create and attach a data disk to each worker node

set -xe

if [ ! -e helper/parameters.sh ]; then
        echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
        exit 1
fi

source helper/parameters.sh

# Remember where files were created for virsh_cleanup.sh

echo "$IMAGES_PATH" > ~/.images_path

rm -f $IMAGES_PATH/test-ocp$OCP_VERSION/*.data

for (( i=0; i<$WORKERS; i++ ))
do
	qemu-img create -f raw $IMAGES_PATH/test-ocp$OCP_VERSION/disk-worker${i}.data ${DATA_DISK_SIZE}G
 	virsh list | grep worker-$i | tail -n +1 | awk -v var="$i" '{system("virsh attach-disk " $2 " --source $IMAGES_PATH/test-ocp$OCP_VERSION/disk-worker" var ".data --target vdc --persistent")}'
done

