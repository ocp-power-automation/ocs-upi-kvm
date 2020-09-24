#!/bin/bash

# Check that oc nodes are ready

# Sometimes a VM will appear in the libvirt 'paused' state and it needs
# to be restarted.  Master nodes and Ceph worker nodes are supposed to
# be resilient, so try to restart them and check status.

# virsh destroy creates a new qemu process.  virsh reboot reuses the
# same process image.  The former is cleaner and therefore more robust.

# Assumes caller sets environment variable KUBECONFIG

set -xe

if [ ! -e helper/parameters.sh ]; then
        echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
        exit 1
fi

source helper/parameters.sh

function wait_vm_reboot ( ) {
	vm="$1"

	echo "Looking up IP Address of VM $vm"

        success=false
        for ((cnt=0; cnt<3; cnt++))
	do
        	ip=$(/usr/local/bin/oc get nodes -o wide | grep $vm | tail -n 1 | awk '{print $6}')
		if [ -n "$ip" ]; then
			cnt=3
			success=true
		else
			if [ "$cnt" == "0" ]; then
				echo "Waiting for IP Address ..."
			fi
			sleep 20
		fi
	done

	if [ "$success" == false ]; then
		echo "ERROR: IP Address of node $vm is unknown"
		exit 1
	fi

	echo "Trying to connect to VM $vm"

        success=false
        for ((cnt=0; cnt<6; cnt++))
        do
                sleep 10

                set +e
                ls_out=$(ssh -o StrictHostKeyChecking=no core@$ip ls /)
                set -e

		if [ -n "$ls_out" ]; then
                        cnt=6
                        success=true
			echo "Connected to VM $vm"
		else
			if [ "$cnt" == "0" ]; then
				echo "Waiting for SSH connection ..."
			fi
			sleep 10
                fi
	done

	if [ "$success" == false ]; then
		echo "ERROR: Unable to connect to node $vm, continuing"
		exit 1
	fi
}

echo "Checking health of master nodes..."
for (( i=0; i<3; i++ ))
do
	vmline=$(virsh list --all | grep master-$i | tail -n 1)
	vm=$(echo $vmline | awk '{print $2}')
	state=$(echo $vmline | awk '{print $3}')
	if [ "$state" == "paused" ]; then
		echo "State of VM $vm is 'paused'"
	 	virsh destroy $vm
		virsh start $vm
		sleep 15
		wait_vm_reboot master-$i 
	fi
done

declare -i master_success=0
for (( i=0; i<3; i++ ))
do
        for (( cnt=0; cnt<3; cnt++ ))
	do
        	state=$(/usr/local/bin/oc get nodes -o wide | grep master-$i | tail -n 1 | awk '{print $2}')
		if [ "$state" == "Ready" ]; then
			cnt=3
			(( master_success=master_success + 1 ))
		else
			sleep 10
		fi
	done
done
if [ "$master_success" -eq "3" ]; then
	echo "Master nodes healthy"
else
	echo "ERROR: all master nodes must be ready"
	oc get nodes
	exit 1
fi

echo "Checking health of worker nodes..."
for (( i=0; i<$WORKERS; i++ ))
do
	vmline=$(virsh list --all | grep worker-$i | tail -n 1)
	vm=$(echo $vmline | awk '{print $2}')
	state=$(echo $vmline | awk '{print $3}')
	if [ "$state" == "paused" ]; then
		echo "State of VM $vm is 'paused'"
	 	virsh destroy $vm
		virsh start $vm
		sleep 15
		wait_vm_reboot worker-$i
	fi
done
declare -i worker_success=0
for (( i=0; i<$WORKERS; i++ ))
do
        for (( cnt=0; cnt<3; cnt++ ))
	do
        	state=$(/usr/local/bin/oc get nodes -o wide | grep worker-$i | tail -n 1 | awk '{print $2}')
		if [ "$state" == "Ready" ]; then
			cnt=3
			(( worker_success = worker_success + 1 ))
		else
			sleep 10
		fi
	done
done
if [ "$worker_success" -eq "$WORKERS" ]; then
	echo "Worker nodes healthy"
else
	echo "ERROR: all requested worker nodes must be not ready"
	oc get nodes
	exit 1
fi
