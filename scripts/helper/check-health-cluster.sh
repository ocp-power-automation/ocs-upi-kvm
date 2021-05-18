#!/bin/bash

# Check that oc nodes are ready

# Sometimes a VM will appear in the libvirt 'paused' state and it needs
# to be restarted.  Master nodes and Ceph worker nodes are supposed to
# be resilient, so try to restart them and check status.

# virsh destroy creates a new qemu process.  virsh reboot reuses the
# same process image.  The former is cleaner and therefore more robust.

# Assumes caller sets environment variable KUBECONFIG

# For PowerVS, we automatically restart nodes as RHCOS kernel boot parameters
# are specified at cluster creation and the nodes are left in DisabledScheduling
# state. Restarting the pods resolves this issue.

set -e

if [ ! -e helper/parameters.sh ]; then
	echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

if [ -e "$WORKSPACE/.bastion_ip" ]; then
	ocp_nodes=( $(oc get nodes | egrep 'master|worker' | awk '{print $1}') )
	if [ -z "$ocp_nodes" ]; then
		echo "Cluster is not online"
		exit 1
	fi
	ocp_status=( $(oc get nodes | egrep 'master|worker' | awk '{print $2}') )

	source $WORKSPACE/.bastion_ip
	bastion_ssh_args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP"
fi

function wait_vm_reboot ( ) {
	vm="$1"

	echo "Looking up IP Address of VM $vm"

	success=false
	for ((cnt=0; cnt<3; cnt++))
	do
		ip=$($WORKSPACE/bin/oc get nodes -o wide | grep $vm | tail -n 1 | awk '{print $6}')
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
		ls_out=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@$ip ls /)
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


echo "Checking master nodes..."

if [ "$PLATFORM" == kvm ]; then
	for (( i=0; i<3; i++ ))
	do
		vmline=$(sudo -sE virsh list --all | grep master-$i | tail -n 1)
		vm=$(echo $vmline | awk '{print $2}')
		state=$(echo $vmline | awk '{print $3}')
		if [ "$state" == paused ]; then
			echo "State of VM $vm is 'paused'"
			sudo -sE virsh destroy $vm
			sudo -sE virsh start $vm
			sleep 15
			wait_vm_reboot master-$i 
		fi
	done
else
	i=0
	for name in "${ocp_nodes[@]}"
	do
		if [[ ! "$name" =~ master ]] || [ "${ocp_status[$i]}" == Ready ]; then
			(( i = i + 1 ))
			continue
		fi

		restart_node="ssh core@$name sudo systemctl restart kubelet.service"

		for (( cnt=0; cnt<10; cnt++ ))
		do
			set +e -x
			ssh $bastion_ssh_args $restart_node
			rc=$?
			set +x -e
			if [ "$rc" == 0 ]; then
				cnt=10
			else
				echo -e "\nTry again in 30 seconds..."
				sleep 30
			fi
		done

		(( i = i + 1 ))
	done
fi

echo "Checking worker nodes..."

if [ "$PLATFORM" == kvm ]; then
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
else
	i=0
	for name in "${ocp_nodes[@]}"
	do
		if [[ ! "$name" =~ worker ]] || [ "${ocp_status[$i]}" == Ready ]; then
			(( i = i + 1 ))
			continue
		fi

		restart_node="ssh core@$name sudo systemctl restart kubelet.service"

		for (( cnt=0; cnt<10; cnt++ ))
		do
			set +e -x
			ssh $bastion_ssh_args $restart_node
			rc=$?
			set +x -e
			if [ "$rc" == 0 ]; then
				cnt=10
			else
				echo -e "\nTry again in 30 seconds..."
				sleep 30
			fi
		done

		(( i = i + 1 ))
	done
fi

declare -i master_success=0
for (( i=0; i<3; i++ ))
do
	for (( cnt=0; cnt<50; cnt++ ))
	do
		node_info=$($WORKSPACE/bin/oc get nodes -o wide | grep master-$i | tail -n 1)
		state=$(echo $node_info | awk '{print $2}')

		if [ "$state" == Ready ]; then
			cnt=50
			(( master_success = master_success + 1 ))
		else
			sleep 15
		fi
	done
done

declare -i worker_success=0
for (( i=0; i<$WORKERS; i++ ))
do
	for (( cnt=0; cnt<50; cnt++ ))
	do
		node_info=$($WORKSPACE/bin/oc get nodes -o wide | grep worker-$i | tail -n 1)
		state=$(echo $node_info | awk '{print $2}')
		ip=$(echo $node_info | awk '{print $6}')

		if [ "$state" == Ready ]; then
			cnt=50
			(( worker_success = worker_success + 1 ))
		else
			sleep 15
		fi
	done
done

if [ "$master_success" -eq "3" ]; then
	echo "Master nodes healthy"
else
	echo "ERROR: all master nodes must be ready"
	$WORKSPACE/bin/oc get nodes
	exit 1
fi

if [ "$worker_success" -eq "$WORKERS" ]; then
	echo "Worker nodes healthy"
else
	echo "ERROR: all requested worker nodes must be ready"
	$WORKSPACE/bin/oc get nodes
	exit 1
fi
