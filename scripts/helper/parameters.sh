#!/bin/bash

export RHID_PASSWORD=${RHID_PASSWORD:=""}

export RHID_USERNAME=${RHID_USERNAME:=""}

export OCP_VERSION=${OCP_VERSION:="4.4"}

export CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="tt.testing"}

export MASTER_DESIRED_CPU=${MASTER_DESIRED_CPU:="4"}
export MASTER_DESIRED_MEM=${MASTER_DESIRED_MEM:="16384"}

export WORKERS=${WORKERS:=2}

export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="4"}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="16384"}

export DATA_DISK_LIST=${DATA_DISK_LIST:=""}		# in GBs

export DATA_DISK_SIZE=${DATA_DISK_SIZE:=100}		# in GBs
export BOOT_DISK_SIZE=${BOOT_DISK_SIZE:=32}		# in GBs

# This is set to the file system with the most space.  Sometimes /home/libvirt/images

export IMAGES_PATH=${IMAGES_PATH:="/var/lib/libvirt/images"}

# This image is obtained from RedHat Customer Portal and then prepared for use

export BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}


# Validate DATA_DISK_LIST upfront so that mistakes are captured early 

if [ -n "$DATA_DISK_LIST" ]; then

	if [[ "$DATA_DISK_LIST" =~ "/" ]]; then
		echo "Error: just specify the disk partition name --- sdi1,sdi2,sdi3"
		exit 1
	fi

	# Convert comma separated list into an array of partition names

	list=${DATA_DISK_LIST//,/ }
	DATA_DISK_ARRAY=($list)
	n=${#DATA_DISK_ARRAY[@]}

	if [ "$n" != "$WORKERS" ]; then
		echo "Error: a single disk partition should be specified per worker node"
		exit 1
	fi

	unique_disks=$(echo $list | xargs -n 1 | sort -u | xargs)
	unique_disk_array=($unique_disks)
	u=${#unique_disk_array[@]}

	if [ "$n" != "$u" ]; then
		echo "Error: invalid disk partition list $DATA_DISK_LIST.  A unique disk partition must be specified per worker node"
		exit 1
	fi

	available_disks=$(lsblk -a)
	for i in $list
	do
		if [[ "$available_disks" != *"$i"* ]]; then 
			echo "Error: invalid disk partition list $DATA_DISK_LIST.  lsblk -a does not show partition $i"
			exit 1
		fi
	done
fi
