#!/bin/bash

arg1=$1

if [[ "$arg1" =~ "help" ]] || [ "$arg1" == "-?" ] ; then
        echo "Usage: $0 [ --devmode ] { block | file }"
	echo "Specify --devmode to test pod and pvc creation without running fio"
        exit 1
fi

if [ "$arg1" == "--devmode" ]; then
	devmode=true
	arg1=$2
else
	devmode=false
fi

io_type=$arg1

case "$io_type" in
	block)
		export STORAGE_CLASS=ocs-storagecluster-ceph-rbd
		;;
	file)
		export STORAGE_CLASS=ocs-storagecluster-cephfs
		;;
	*)
		echo "Usage: $0 [ --devmode ] { block | file }"
		exit 1
esac

if [ -z "$WORKSPACE" ]; then
        cwdir=$(pwd)
        cmdpath=$(dirname $0)
        if [ "$cmdpath" == "." ]; then
                if [ -d ocs-upi-kvm ]; then
                        export WORKSPACE=$cwdir
                else
                        export WORKSPACE=$cwdir/../..
                fi
        elif [[ "$cmdpath" =~ "ocs-upi-kvm/samples" ]]; then
                export WORKSPACE=$cwdir/$cmdpath/../..
        elif [[ "$cmdpath" =~ "samples" ]]; then
                export WORKSPACE=$cwdir/..
        elif [ -d ocs-upi-kvm ]; then
                export WORKSPACE=$cwdir
        else
                echo "Could not find ocs-upi-kvm directory"
                exit 1
        fi
fi

if [ -e $WORKSPACE/env-ocp.sh ]; then
	source $WORKSPACE/env-ocp.sh
fi

function create_pods () {
	export PROXY_NAME=$(oc get proxy | head -2 | tail -1 | awk '{print $1}')
	export BASTION_HTTP_PROXY=$(oc describe proxy/$PROXY_NAME | grep "Http Proxy" | tail -1 | awk '{ print $3}')
	export NO_PROXY=$(oc describe proxy/cluster | grep "No Proxy" | tail -1 | awk '{ print $3}')

	echo "Creating fio pods ..."
	i=0
	while (( i < num_workers ))
	do
		export WORKER_NAME="${workers[$i]}"

		j=0
		while (( j < num_pods_per_worker ))
		do
			export PVC_NAME=fio-w${i}-pvc${j}
			export POD_NAME=fio-w${i}-p${j}

			cat $WORKSPACE/ocs-upi-kvm/files/perf-fio/fiopod.yaml.in | envsubst > $WORKSPACE/fiopod.yaml
			oc create -f $WORKSPACE/fiopod.yaml

			pvcs+=( $PVC_NAME )
			pods+=( $POD_NAME )

			(( j = j + 1 ))
		done
		(( i = i + 1 ))
	done
}

function install_fio_in_pods () {
	cat $WORKSPACE/ocs-upi-kvm/files/perf-fio/run_fio_pod.sh.in | envsubst > $WORKSPACE/run_fio_pod.sh
	chmod a+x $WORKSPACE/run_fio_pod.sh

	echo "Preparing fio pods ..."
	npods=${#pods[@]}
	i=0
	while (( i < npods ))
	do
		pod_name=${pods[$i]}

		oc wait --for=condition=Ready pod/$pod_name --timeout=30s > /dev/null 2>&1

		if [ "$devmode" == false ]; then
			oc rsh $pod_name /usr/bin/apt-get update > /dev/null 2>&1
			oc rsh $pod_name /usr/bin/apt-get -y install fio procps > /dev/null 2>&1
			oc cp $WORKSPACE/run_fio_pod.sh $pod_name:run_fio_pod.sh
		fi

		(( i = i + 1 ))
	done
}

function run_fio_in_pods () {
	npods=${#pods[@]}
	i=0
	while (( i < npods ))
	do
		pod_name=${pods[$i]}
		echo "Invoking fio command on pod $pod_name"

		if [ "$devmode" == true ]; then
			oc rsh $pod_name hostname
		else
			oc rsh $pod_name ./run_fio_pod.sh &
		fi

        	(( i = i + 1 ))
	done
}

function wait_for_fio_pods_to_complete () {

	if [ "$devmode" == true ]; then
		return
	fi

	sleep 30m					# First part is slow - the fill

	npods=${#pods[@]}
	pod_done=0
	while (( pod_done < npods ))
	do
		i=0
		while (( i < npods ))
		do
			pod_name=${pods[$i]}

			set +e
			oc rsh $pod_name ls fio-results.tar >/dev/null 2>&1
			rc=$?
			if [ "$rc" == 0 ]; then
				if [ ! -e $fio_results_dir/$pod_name/fio-results-$pod_name.tar ]; then
					echo "Transferring fio results for $pod_name"
					mkdir -p $fio_results_dir/$pod_name
					oc cp $pod_name:fio-results.tar $fio_results_dir/$pod_name/fio-results-$pod_name.tar
				fi
				(( pod_done = pod_done + 1 ))
			else
				results=$(oc rsh $pod_name ls -rt results/ 2>/dev/null | wc -l)
				echo "Still running -- ${pod_name} -- working on test $results of 12"
			fi
			set -e

			(( i = i + 1 ))
		done
		if (( pod_done < npods )); then
			echo -e "Sleeping 10 minutes... total pods=$npods pods comleted=$pod_done\n"
			sleep 10m
		fi
	done
}

function delete_pods () {
	echo "Deleting fio pods and pvcs..."

	sleep 5s
	oc get pod | grep ^fio | awk '{ print $1 }' | xargs oc delete pod
	oc get pvc | grep ^fio | awk '{ print $1 }' | xargs oc delete pvc
	exit
}


# FIO pods are created in the default project

oc project default >/dev/null 2>&1

# Determine how much ceph memory is available in the pool

ceph_tools=$( oc -n openshift-storage get pods | grep rook-ceph-tools | awk '{print $1}' ) 
max_avail_GiB=$( oc -n openshift-storage rsh $ceph_tools ceph df | grep ocs-storagecluster-cephblockpool | awk '{print $9}' )

# Pool may have other PVC allocations for registries.  Try to stay below 75% to avoid certs alerts, etc

workers=( $(oc get nodes | grep worker | awk '{print $1}' ) )
num_workers="${#workers[@]}"

use_GiB_per_worker=$(( max_avail_GiB * 60 / 100 / num_workers ))

# We need to know the amount of memory each worker node has in order to create a high memory load

worker0="${workers[0]}"
worker_node_mem=$(oc debug node/$worker0 -- chroot /host lsmem 2>/dev/null | grep "^Total online memory" | awk '{ print $4 }' | sed 's/G//')

# Determine the number of pods and the amount of storage in each pod's pvc.  Assume 16 GiB pvc is minimal viable size

if [ "$devmode" == true ]; then
	num_pods_per_worker=1
	pvc_size=16
else
	min_pvc_allocated_per_worker=$(( worker_node_mem * 75 / 100 ))
	if (( use_GiB_per_worker < min_pvc_allocated_per_worker )); then
		echo "ERROR: Available storage in ceph blockpool is insufficient to run FIO test.  Increase the size of worker node data disks!"
		echo "       use_GiB_per_worker=$use_GiB_per_worker must be >= min_pvc_allocated_per_worker=$min_pvc_allocated_per_worker"
		exit 1
	fi

	num_pods_per_worker=16
	pvc_size=$(( use_GiB_per_worker / num_pods_per_worker ))
	while (( pvc_size < 16 ))
	do
		(( num_pods_per_worker = num_pods_per_worker / 2 ))
		(( pvc_size = pvc_size * 2 ))
	done
fi
	
total_pods=$(( num_pods_per_worker * num_workers ))
echo "Available ceph storage: $max_avail_GiB"
echo "Total fio pods: $total_pods"
echo "PVC size: ${pvc_size}G"
echo "Number of worker nodes: $num_workers"
echo "Memory per worker node: ${worker_node_mem}G"

# These enviroment variables are used in fiopod.yaml.in

export PVC_SIZE=${pvc_size}Gi

# These environment variables are used in the run_fio.sh file

fsize=$(( pvc_size * 70 / 100 ))
export FSIZE=${fsize}G

echo "Size of fio file: $FSIZE"

log_date=$(date "+%d%H%M")
fio_results_dir=$WORKSPACE/fio-results/$io_type/$log_date
rm -rf $fio_results_dir
mkdir -p $fio_results_dir

echo "Fio results directory: $fio_results_dir"
echo "Fio run number: $log_date"

pods=()
pvcs=()

trap delete_pods SIGINT SIGTERM

create_pods

install_fio_in_pods

run_fio_in_pods

wait_for_fio_pods_to_complete

delete_pods

