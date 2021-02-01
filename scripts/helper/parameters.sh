#!/bin/bash

ulimit -s unlimited

# Either username / password or org / key.  Username / password takes precedence

export RHID_USERNAME=${RHID_USERNAME:=""}
export RHID_PASSWORD=${RHID_PASSWORD:=""}

export RHID_ORG=${RHID_ORG:=""}
export RHID_KEY=${RHID_KEY:=""}

export OCP_VERSION=${OCP_VERSION:="4.6"}

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


# A second DNS forwarder - can and should be overridden if deployment will
# happen behind a firewall

export DNS_BACKUP_SERVER=${DNS_BACKUP_SERVER:="1.1.1.1"}

# If chrony is enabled, then the list of ntp servers must be specified

export CHRONY_CONFIG=${CHRONY_CONFIG:="false"}
export CHRONY_CONFIG_SERVERS=${CHRONY_CONFIG_SERVERS:="{\"server\": \"0.rhel.pool.ntp.org\",\"options\": \"iburst\"},{\"server\": \"1.rhel.pool.ntp.org\",\"options\": \"iburst\"}"}


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

export CLUSTER_CIDR=${CLUSTER_CIDR:="192.168.88.0/24"}
export CLUSTER_GATEWAY=${CLUSTER_GATEWAY:="192.168.88.1"}
export BASTION_IP=${BASTION_IP:="192.168.88.2"}

# IMPORTANT: Increment this generation count every time that the kvm_setup_host.sh file is changed

export KVM_SETUP_GENCNT=5

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

# Determine the PLATFORM.  Used for applying patches and performance optimization

kvm_present=$(/usr/sbin/lsmod | grep kvm)
if [ -n "$kvm_present" ]; then
        PLATFORM=kvm
else
        PLATFORM=powervs
fi

# Virtual memory performance of VMs is greatly improved by using hugepages
# as this memory is always resident and is not paged by the host kernel.
# It is reserved for one applications use.  Accessing this memory is orders
# of magnitude faster as 1 TLB needs to be mapped for each hugepage as opposed
# to 100000s of TLBs of smaller pages that would otherwise need to be mapped.
# This capability is provided only for worker nodes as it is non-sharable and
# it adds up to a large amount.  Further, to get the best results, one needs
# to over allocate by a worker node as the memory is split across 2 numa nodes.
# If the extra memory is not pre-allocated, then the final worker node gets
# a split of huge pages from 2 pools.  Whenever this node (many threads) is
# scheduled, it pollutes the processor cache and the threads that are subsequently
# scheduled pay the penalty as they have to rebuild memory affinity.  So, extra
# memory should be allocated to avoid the situation to improve over all performance,
# when there is an odd number of worker nodes.  This feature should only be
# enabled on servers with 512 GBs of memory.  The minimum required is three worker
# nodes worth of hugepages.

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
