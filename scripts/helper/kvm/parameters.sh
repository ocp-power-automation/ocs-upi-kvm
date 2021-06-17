#!/bin/bash

export IMAGES_PATH=${IMAGES_PATH:="/var/lib/libvirt/images"}
export BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}

export DATA_DISK_SIZE=${DATA_DISK_SIZE:=256}				# in GBs
export FORCE_DISK_PARTITION_WIPE=${FORCE_DISK_PARTITION_WIPE:="false"}
export DATA_DISK_LIST=${DATA_DISK_LIST:=""}				# in GBs

# Master node vcpus are not bound to a NUMA Node (socket) which can lead to poor
# system performance as cpu contention grows, so the number of master vcpus should
# be less than the number of cores per socket to minimize remote node scheduling.
# P8 has 10 cores per socket and P9 has 16-22 depending on the model.  Unlike master
# nodes, worker node vcpus are bound to NUMA sockets so they can be scaled higher.

coresPerSocket=$(lscpu | grep "^Core(s) per socket" | awk '{print $4}')

export MASTER_DESIRED_CPU=${MASTER_DESIRED_CPU:=8}
export MASTER_DESIRED_MEM=${MASTER_DESIRED_MEM:=24576}
export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:=$coresPerSocket}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:=65536}

export CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="tt.testing"}

export CLUSTER_CIDR=${CLUSTER_CIDR:="192.168.88.0/24"}
export CLUSTER_GATEWAY=${CLUSTER_CIDR/0\/24/1}
export BASTION_IP=${CLUSTER_CIDR/0\/24/2}

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

########################### Internal variables & functions #############################


# IMPORTANT: Increment KVM_SETUP_GENCNT if the setup-kvm-host.sh file changes

KVM_SETUP_GENCNT=7

OCP_PROJECT=ocp4-upi-kvm

case $OCP_VERSION in
4.4|4.5)
	export OCP_PROJECT_COMMIT=origin/release-4.5
	;;
*)
	set +e
	git branch -r | grep release-$OCP_VERSION
	rc=$?
	set -e
	if [ "$rc" == 0 ]; then
 		export OCP_PROJECT_COMMIT=release-$OCP_VERSION
	else
 		export OCP_PROJECT_COMMIT=origin/master
 	fi
esac

export OCS_CI_ON_BASTION=false
export CMA_PERCENT=0

export RHCOS_IMAGE=rhcos${RHCOS_SUFFIX}.qcow2

# Virtual memory performance of VMs is greatly improved by using hugepages as this memory is always resident and
# is not paged by the host kernel.  Accessing this memory is orders of magnitude faster as 1 TLB needs to be mapped
# for each hugepage as opposed to 100000s of TLBs for smaller pages.  This capability is provided only for worker
# nodes as there is not enough system memory available for more than three worker nodes.  In fact, one has to over
# allocate as there are two memory pools, one per socket, so the alignment is only optimal for an even number of
# worker nodes.  If one allocated exactly the amount needed for three workers, then the last worker would get half of
# its memory from each pool.  As a consequence, this feature should only be enabled on servers with 512 GBs of memory.

export HUGE_PAGE_POOL_TOTAL=${HUGE_PAGE_POOL_TOTAL:="256"}

ARCH=$(lscpu | grep "^Model name" | awk '{print $3}' | sed 's/,//')

# HugePageSize is the expected page size that we configure.  If a different
# value is configured assume it is for other purposes.

if [ "$ARCH" == "POWER8" ]; then
        HugePageSize=16M
        (( HugePageBytes = 16 * 1024 * 1024 ))
else
        HugePageSize=1G
        (( HugePageBytes = 1024 * 1024 * 1024 ))
fi

actualHugePageSize=$(grep Hugepagesize /proc/meminfo | awk '{print $2}') 

if (( (actualHugePageSize * 1024) != HugePageBytes )); then
	export ENABLE_HUGE_PAGES=false
fi

function enable_hugepages ( ) {

	freeHugePages=$(cat /proc/meminfo | grep HugePages_Free | awk '{print $2}')
	minHugePages=$(( WORKER_DESIRED_MEM * 1024 * 1024 * 3 / HugePageBytes ))

	if (( freeHugePages >= minHugePages )); then
		export ENABLE_HUGE_PAGES=${ENABLE_HUGE_PAGES:="true"}
	else
		export ENABLE_HUGE_PAGES=${ENABLE_HUGE_PAGES:="false"}
	fi
	echo "ENABLE_HUGE_PAGES=$ENABLE_HUGE_PAGES"
}

function prepare_new_cluster_delete_old_cluster ( ) {

	KVM_SETUP_GENCNT_INSTALLED=-1

	# Validate the KVM host server runtime

	invoke_kvm_setup=false
	if [ ! -e ~/.kvm_setup ]; then
		invoke_kvm_setup=true
	else
		source ~/.kvm_setup
		if [[ "$KVM_SETUP_GENCNT_INSTALLED" -lt "$KVM_SETUP_GENCNT" ]]; then
			invoke_kvm_setup=true
		fi
	fi

	if [ "$invoke_kvm_setup" == "true" ]; then
		echo "Invoking setup-kvm-host.sh"
		sudo -sE helper/kvm/setup-kvm-host.sh
		echo "KVM_SETUP_GENCNT_INSTALLED=$KVM_SETUP_GENCNT" > ~/.kvm_setup
	fi

	# Validate the presense of required files

	file_present $IMAGES_PATH/$BASTION_IMAGE
	if [[ ! -e $WORKSPACE/$BASTION_IMAGE ]] && [[ "$file_rc" != 0 ]]; then
		echo "ERROR: Missing $BASTION_IMAGE.  Get it from https://access.redhat.com/downloads/content/479/ and prepare it per README"
		exit 1
	fi
	if [[ -e $WORKSPACE/$BASTION_IMAGE ]] && [[ "$file_rc" != 0 ]]; then
		sudo -sE mkdir -p $IMAGES_PATH
		sudo -sE mv -f $WORKSPACE/$BASTION_IMAGE $IMAGES_PATH
	fi

	# Get the RHCOS image associated with the specified OCP Version and copy it to
	# IMAGES_PATH and normalize the name of the image with a soft link with RHCOS_SUFFIX
	# so that it referenced with a common naming scheme.  This image is the boot disk of
	# each VM and needs to be resized to accomodate OCS.  There is no penalty for specifying
	# a larger size than what is actually needed as the qcow2 image is a sparse file.

	file_present $IMAGES_PATH/rhcos${RHCOS_SUFFIX}.qcow2
	if [ "$file_rc" != 0 ]; then
		pushd $WORKSPACE
		rm -f rhcos*qcow2.gz
		if [ -n "$RHCOS_RELEASE" ]; then
			wget -nv https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/$RHCOS_VERSION/$RHCOS_RELEASE/rhcos-$RHCOS_RELEASE-ppc64le-qemu.ppc64le.qcow2.gz
		else
			wget -nv https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/pre-release/latest-$RHCOS_VERSION/rhcos-qemu.ppc64le.qcow2.gz
		fi
		file=$(ls -1 rhcos*qcow2.gz | tail -n 1)
		echo "Unzipping $file"
		gunzip -f $file
		file=${file/.gz/}

		echo "Resizing $file (VM boot image) to 40G"
		qemu-img resize $file 40G
		sudo -sE mv -f $file $IMAGES_PATH

		sudo -sE ln -sf $IMAGES_PATH/$file $IMAGES_PATH/rhcos${RHCOS_SUFFIX}.qcow2
		popd
	fi

	# Remove pre-existing cluster.  We are going to create a new one

	echo "Invoking virsh-cleanup.sh"
	sudo -sE helper/kvm/virsh-cleanup.sh

	# Enable use of huge pages.  Minimum requirement covers 3 worker nodes.  Must be done after cluster teardown

	enable_hugepages
}

function setup_remote_oc_use () {
	return
}

function config_ceph_for_nvmessd () {
	return
}
