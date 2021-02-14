#!/bin/bash

# Create and attach a data disk to each worker node

# One can attach a disk partition or a qcow2 file.  The qcow2 method is
# the default, which can be overridden by specifying a comma separated list
# of disk partitions via the environment variable DATA_DISK_LIST.

# Assumes caller sets environment variable KUBECONFIG

set -e

user=$(whoami)
if [ "$user" != "root" ]; then
	echo "You must be root user to invoke this script $0"
	exit 1
fi

if [ ! -e helper/parameters.sh ]; then
	echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

VDISK=${VDISK:="vdc"}

echo KUBECONFIG=$KUBECONFIG
echo WORKSPACE=$WORKSPACE

if [[ "$DATA_DISK_SIZE" -le "0" ]]; then
	echo "No data disks will be created"
	exit
fi

# Schedule worker nodes on second NUMA node if disk are file backed
# as the data is buffered.  Their proximity to storage adapters is
# less important, so optimize towards network and master nodes.  This
# means 2 worker nodes are placed on the second numa node along with
# one master node.  The first numa node holds one worker and two
# masters.  This placement results in the fewest number of soft irqs
# which lowers latency.  If disks are backed by devices, the reverse
# happens.  2 workers on the first NUMA node and 1 on the second.

if [ -n "$DATA_DISK_ARRAY" ]; then
	primary=$(lscpu | grep "NUMA node0 CPU" | awk '{print $4}')
	secondary=$(lscpu | grep "NUMA node8 CPU" | awk '{print $4}')

else
	secondary=$(lscpu | grep "NUMA node0 CPU" | awk '{print $4}')
	primary=$(lscpu | grep "NUMA node8 CPU" | awk '{print $4}')
fi

# If OCS is configured, give more time for each node to recover
# before modifying the next one

set +e
ocs_configured=$($WORKSPACE/bin/oc get projects | grep ^openshift-storage)
set -e
if [ -n "$ocs_configured" ]; then
	delay=60
else
	delay=10
fi

if [ -z "$DATA_DISK_ARRAY" ]; then
	# Remember where data files will be created for virsh_cleanup.sh
	echo "$IMAGES_PATH" > $WORKSPACE/.images_path
	# Remove old images in case virsh_cleanup.sh is not run
	rm -f $IMAGES_PATH/test-ocp$SANITIZED_OCP_VERSION/*.data
fi

# Add vdisk to worker nodes and tune VM worker node performance, since they have to be rebooted

for (( i=0; i<$WORKERS; i++ ))
do
	if [ -n "$DATA_DISK_ARRAY" ]; then
		disk_path=/dev/${DATA_DISK_ARRAY[$i]}
		if [ "$FORCE_DISK_PARTITION_WIPE" == "true" ]; then
			echo "Wiping $disk_path.  This takes ~30 minutes for a 500G disk..."
			wipe -I $disk_path
			echo "Completed disk wipe of $disk_path"
			DATA_DISK_SIZE=$(fdisk -l $disk_path | head -n 1 | awk '{print $3}')
			DATA_DISK_SIZE=${DATA_DISK_SIZE/\.*/}
		fi
	else
		disk_path=$IMAGES_PATH/test-ocp$SANITIZED_OCP_VERSION/disk-worker${i}.data-$VDISK
		if [ -e $disk_path ]; then
			echo "WARNING: Overwriting data disk file $disk_path"
		fi
	fi

	echo "Creating data disk $disk_path of size ${DATA_DISK_SIZE}G"
	qemu-img create -f raw $disk_path ${DATA_DISK_SIZE}G

	vm=$(virsh list --all | grep worker-$i | tail -n 1 | awk '{print $2}')

	echo "Attaching data disk to $vm at $VDISK"
	virsh attach-disk $vm --source $disk_path --target $VDISK --persistent

	set -x
        set +e
	virsh dumpxml $vm | grep hugepages 
	rc=$?
	if [[ "$rc" != 0 ]] && [[ "$ENABLE_HUGE_PAGES" == "true" ]]; then

		# These performance enhancements are done once per VM based on a user
		# action -- enabling hugepages.  A complete power off operation is
		# required to activate these changes.  virsh destroy is potentially
		# destructive as cached file system data may be lost, but in this case
		# there is none as the cluster has just been installed.

		freeHugePages=$(cat /proc/meminfo | grep HugePages_Free | awk '{print $2}')
		numHugePagesNeeded=$(( WORKER_DESIRED_MEM * 1024 * 1024 / HugePageBytes ))

		if (( numHugePagesNeeded <= freeHugePages )); then
			echo "Enabling huge pages"
			virt-xml $vm --edit --memory hugepages=yes
		fi

		virsh dumpxml $vm | grep "name='vhost'"
        	rc=$?
		if [ "$rc" != 0 ]; then
			echo "Enabling vhost queues=4"
			virt-xml $vm --edit --network driver.name=vhost,driver.queues=4
		fi

		# Bias placement of worker nodes on the type of underlying storage.  If
		# file backed disks are used, storage adapter IO is less important as data
		# is cached in the host filesystem.

		virsh dumpxml $vm | grep cpuset
		rc=$?
		if [ "$rc" != 0 ]; then
			if (( i % 2 )); then
				cpuset=$secondary
			else
				cpuset=$primary
			fi
			echo "Binding to cpuset=$cpuset"
			virt-xml $vm --edit --vcpu vcpu.cpuset=$cpuset
		fi

		virsh destroy $vm
		sync && sleep 2
		virsh start $vm
	else
		# This script may also be invoked while OCS is running.  A reboot
		# operation ensures that a clean shutdown is performed.

		virsh reboot $vm
	fi
	set -e
	set +x

	sleep $delay
done

# Wait for each node to become ready

echo "Waiting up to ${delay}0 seconds for each worker node to become ssh accessible"

for (( i=0; i<$WORKERS; i++ ))
do
	vm=$(virsh list --all | grep worker-$i | awk '{print $2}' | tail -n 1)

	success=false
	for ((cnt=0; cnt<3; cnt++))
	do
		ip=$($WORKSPACE/bin/oc get nodes -o wide | grep worker-$i | tail -n 1 | awk '{print $6}')
		if [ -n "$ip" ]; then
			cnt=3
			success=true
		else
			sleep 10
		fi
	done

	if [ "$success" == false ]; then
		echo "WARNING: IP Address for VM $vm is not known, continuing anyway"
		continue
	fi

	success=false
	for ((cnt=0; cnt<10; cnt++))
	do
		sleep $delay

		set +e
		ls_out=$(su - $SUDO_USER -c "ssh -o StrictHostKeyChecking=no core@$ip ls /")
		set -e

		if [ -n "$ls_out" ]; then
			cnt=10
			success=true
		fi
	done

	if [ "$success" == false ]; then
		echo "WARNING: VM $vm at $ip is not ssh accessible, continuing anyway"
	else
		echo "VM $vm at $ip is ssh accessible"
	fi
done

