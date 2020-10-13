#!/bin/bash

ulimit -s unlimited

# Either username / password or org / key.  Username / password takes precedence

export RHID_USERNAME=${RHID_USERNAME:=""}
export RHID_PASSWORD=${RHID_PASSWORD:=""}

export RHID_ORG=${RHID_ORG:=""}
export RHID_KEY=${RHID_KEY:=""}

export OCP_VERSION=${OCP_VERSION:="4.5"}

export CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="tt.testing"}

export MASTER_DESIRED_CPU=${MASTER_DESIRED_CPU:="4"}
export MASTER_DESIRED_MEM=${MASTER_DESIRED_MEM:="16384"}

export WORKERS=${WORKERS:=3}

export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="4"}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="16384"}

# Parameters for data disks backed by disk partitions

export FORCE_DISK_PARTITION_WIPE=${FORCE_DISK_PARTITION_WIPE:="false"}
export DATA_DISK_LIST=${DATA_DISK_LIST:=""}		# in GBs

# Parameters for data disks backed by files

export DATA_DISK_SIZE=${DATA_DISK_SIZE:=256}		# in GBs

# This is set to the file system with the most space.  Sometimes /home/libvirt/images

export IMAGES_PATH=${IMAGES_PATH:="/var/lib/libvirt/images"}

# This image is obtained from RedHat Customer Portal and then prepared for use

export BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}


############################## Validate Input Parameters ###############################

# Validate DATA_DISK_LIST so that mistakes are captured early

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

############################## Internal variables & functions ###############################

# Sanitize the user specified ocp version which is included in the cluster name.  The cluster
# name should not include dots (.) as this is reflected in the fully qualified hostname which
# confuses DHCP.  For example, bastion-test-ocp4.6.tt.testing.  The dot in ocp version is
# changed to a dash(-) to solve this problem

export SANITIZED_OCP_VERSION=${OCP_VERSION/./-}

# WORKSPACE is a jenkins environment variable denoting a dedicated execution environment
# that does not overlap with other jobs.  For this project, there are required input and
# output files that should be placed outside the git project itself.  If a workspace
# is not defined, then assume it is the parent directory of the project.

if [ -z "$WORKSPACE" ]; then
	cdir="$(pwd)"
	if [[ "$cdir" =~ "ocs-upi-kvm" ]]; then
		cdirnames=$(echo $cdir | sed 's/\// /g')
		dir=""
		for i in $cdirnames
		do
			if [ "$i" == "ocs-upi-kvm" ]; then
				break
			fi
			dir="$dir/$i"
		done
		WORKSPACE="$dir"
	elif [ -e ocs-upi-kvm ]; then
		WORKSPACE="$cdir"
	else
		WORKSPACE="$HOME"
	fi
fi

# Files in IMAGES_PATH are not visible to non-root users.  This provides a lookup function

file_rc=
function file_present ( ) {
	file=$1	

	set +e
	ls_out=$(sudo ls $1)
	set -e

	if [ -n "$ls_out" ]; then
		file_rc=0
	else
		file_rc=1
	fi
}
