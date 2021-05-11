#!/bin/bash

arg1=$1

if [[ "$arg1" =~ "help" ]] || [ "$arg1" == "-?" ] ; then
	echo "Usage: $0 [ --devmode ] [ --tuneceph ] [ --fioworkers n ] { block | file }"
	echo "Specify --devmode to test pod and pvc creation without running fio"
	echo "Specify --tuneceph to apply ssd settings for ceph on Power.  Beware there is no reset option.  Still under development...!"
	exit 1
fi

dev_mode=false
tune_ceph=false
fio_workers=-1
while :
do
	case "$arg1" in
	--devmode)
		dev_mode=true
		shift
		arg1=$1
		;;
	--tuneceph)
		tune_ceph=true
		shift
		arg1=$1
		;;
	--fioworkers)
		shift
		fio_workers=$1
		shift
		arg1=$1
		;;
	block)
		io_type=$arg1
		export STORAGE_CLASS=ocs-storagecluster-ceph-rbd
		break
		;;
	file)
		io_type=$arg1
		export STORAGE_CLASS=ocs-storagecluster-cephfs
		break
		;;
	*)
		echo "Usage: $0 [ --devmode ] [ --tuneceph ] [ --fioworkers n ] { block | file }"
		echo "Specify --devmode to test pod and pvc creation without running fio"
		echo "Specify --tuneceph to apply ssd settings for ceph on Power.  Beware there is no reset option.  Still under development...!"
		exit 1
		;;
	esac
done

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

ceph_tools=$( oc -n openshift-storage get pods | grep rook-ceph-tools | awk '{print $1}' )
if [ -z "$ceph_tools" ]; then
	echo "rook-ceph-tools pod must be installed!"
	exit 1
fi

if [ "$tune_ceph" == true ] && [ -e helper/parameters.sh ]; then
	export PLATFORM=${PLATFORM:=powervs}
	source helper/parameters.sh
	config_ceph_for_nvmessd
fi

# The user can specify the number of worker nodes to use when running fio via the
# parameter --fioworkers.  The last N worker nodes as reported by the oc command are used.
# By default, OCS is installed on the first three worker nodes.  If this parameter is
# not specified, then all worker nodes are used.

worker_list=( $(oc get nodes | grep worker | awk '{print $1}' ) )
num_workers="${#worker_list[@]}"

if [ "$fio_workers" == -1 ]; then
	worker_index=0
	fio_workers=$num_workers
else
	if (( fio_workers > num_workers )); then
		echo "Invalid argument: --fioworkers n, $fio_workers > num_workers=$num_workers"
		exit 1
	fi
	(( worker_index = num_workers - fio_workers ))
fi



function create_pods () {
	export PROXY_NAME=$(oc get proxy | head -2 | tail -1 | awk '{print $1}')
	export BASTION_HTTP_PROXY=$(oc describe proxy/$PROXY_NAME | grep "Http Proxy" | tail -1 | awk '{ print $3}')
	export NO_PROXY=$(oc describe proxy/cluster | grep "No Proxy" | tail -1 | awk '{ print $3}')

	echo "Creating fio pods ..."
	i=$worker_index
	while (( i < num_workers ))
	do
		export WORKER_NAME="${worker_list[$i]}"

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

		if [ "$dev_mode" == false ]; then
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

		if [ "$dev_mode" == true ]; then
			oc rsh $pod_name hostname
		else
			oc rsh $pod_name ./run_fio_pod.sh &
		fi

        	(( i = i + 1 ))
	done
}

function wait_for_fio_pods_to_complete () {

	if [ "$dev_mode" == true ]; then
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
			echo -e "Sleeping 5 minutes... total pods=$npods pods comleted=$pod_done\n"
			sleep 5m
		fi
	done
}

function delete_pods () {
	echo "Deleting fio pods and pvcs..."

	sleep 5s
	oc get pod | grep ^fio | awk '{ print $1 }' | xargs oc delete pod
	oc get pvc | grep ^fio | awk '{ print $1 }' | xargs oc delete pvc

	echo "Fio results directory: $fio_results_dir"

	exit
}

# FIO pods are created in the default project

oc project default >/dev/null 2>&1

# Determine how much ceph memory is available in the pool

max_avail_GiB=$( oc -n openshift-storage rsh $ceph_tools ceph df | grep ocs-storagecluster-cephblockpool | awk '{print $9}' )

use_GiB_per_worker=$(( max_avail_GiB * 80 / 100 / fio_workers ))

# Determine the amount of system memory on ceph worker nodes

ceph_node=$(oc get pods -n openshift-storage  -o wide | grep osd | head -n 1 | awk '{print $7}')
worker_node_mem=$(oc debug node/$ceph_node -- chroot /host lsmem 2>/dev/null | grep "^Total online memory" | awk '{ print $4 }' | sed 's/G//')

# Determine the number of pods and the amount of storage in each pod's pvc.  Assume 16 GiB pvc is minimal viable size

min_pvc_allocated_per_worker=$(( worker_node_mem * 80 / 100 ))
if (( use_GiB_per_worker < min_pvc_allocated_per_worker )); then
	echo "ERROR: Available storage in ceph blockpool is insufficient to run FIO test.  Increase the size of worker node data disks!"
	echo "       use_GiB_per_worker=$use_GiB_per_worker must be >= min_pvc_allocated_per_worker=$min_pvc_allocated_per_worker"
	exit 1
fi

if [ "$dev_mode" == true ]; then
	dev_mode_output="dev_mode"
	num_pods_per_worker=1
else
	num_pods_per_worker=16
fi

pvc_size=$(( use_GiB_per_worker / num_pods_per_worker ))
while (( pvc_size < 16 ))
do
	(( num_pods_per_worker = num_pods_per_worker / 2 ))
	(( pvc_size = pvc_size * 2 ))
done
	
total_pods=$(( num_pods_per_worker * fio_workers ))
echo "Available ceph storage: ${max_avail_GiB}G"
echo "Total fio pods: $total_pods $dev_mode_output"
echo "PVC size: ${pvc_size}G"
echo "Number of worker nodes: $num_workers"
echo "Number of fio worker nodes: $fio_workers"
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


pods=()
pvcs=()

trap delete_pods SIGINT SIGTERM

create_pods

install_fio_in_pods

run_fio_in_pods

wait_for_fio_pods_to_complete

delete_pods

