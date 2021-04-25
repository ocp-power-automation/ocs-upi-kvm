#!/bin/bash

# This script may be relocated to the parent directory of ocs-upi-kvm project and
# edited to invoke a different sequence.  Sometimes to comment a line of execution
# to avoid recreating the cluster and other times to invoke ocs-ci with different
# parameters.  This script is relocatable, so the project itself is not modified.


# These environment variables are required for all platforms

export PLATFORM=powervs

#export RHID_USERNAME=<your registered username>		# Change this line or preset in shell
#export RHID_PASSWORD=<your password>				# Edit or preset


# These environment variables are optional for all platforms

export OCP_VERSION=${OCP_VERSION:=4.7}                          # 4.5, 4.7, and 4.8 are also supported
export OCS_VERSION=${OCS_VERSION:=4.7}

export MASTER_DESIRED_CPU=1.25
export MASTER_DESIRED_MEM=48
export WORKER_DESIRED_CPU=2.5
export WORKER_DESIRED_MEM=96

# These are optional for KVM OCP cluster create.  Default values are shown

#export IMAGES_PATH=/var/lib/libvirt/images                     # File system space is important.  Else try /home/libvirt/images
#export BASTION_IMAGE=rhel-8.2-update-2-ppc64le-kvm.qcow2
#if [ -z "$DATA_DISK_LIST" ]; then                              # if not set, then file backed disks are used
#       export DATA_DISK_LIST="sdc1,sdd1,sde1"                  # Each worker node requires a dedicated disk partition
#       export FORCE_DISK_PARTITION_WIPE=true                   # Default is false
#fi


# These environments variables are required for PowerVS OCP cluster create

#export PVS_API_KEY=<your key>
#export PVS_SERVICE_INSTANCE_ID=<your instance id>              # Click eye icon on the left of IBM CLoud resource list, copy GUID field


# These are optional for PowerVS OCP cluster create.  Default values are shown

#export CLUSTER_ID_PREFIX=$RHID_USERNAME                        # Actually first 6 chars of rhid_username + ocp version
#export PVS_SUBNET_NAME=ocp-net
#export PVS_REGION=lon  	                                # Or tok/tok04 sao/sao01 depending on service instance id
#export PVS_ZONE=lon06
#export SYSTEM_TYPE=s922
#export PROCESSOR_TYPE=shared
#export BASTION_IMAGE=rhel-83-02182021
export WORKER_VOLUME_SIZE=768
export USE_TIER1_STORAGE=true

# These are optional for PowerVS ocs-ci.  Default values are shown

#export OCS_CI_ON_BASTION=false                                 # When true, ocs-ci runs on bastion node
                                                                # May help with intermittent network problems and testcase timeouts

function config_ceph_for_nvmessd () {
        echo "Retrieving ceph tools" | tee $WORKSPACE/ceph-fio-config.log
        ceph_tools=$( oc -n openshift-storage get pods | grep rook-ceph-tools | awk '{print $1}' )

        echo "Dumping ceph configurartion before nvme/ssd enhancements" | tee -a $WORKSPACE/ceph-fio-config.log

        oc -n openshift-storage rsh $ceph_tools ceph config dump | tee -a $WORKSPACE/ceph-fio-config.log

        echo "Performing ceph configuration nvme/ssd enhancements" | tee -a $WORKSPACE/ceph-fio-config.log

        oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_op_num_threads_per_shard 2 | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_op_num_shards 8 | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_recovery_sleep 0 | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_snap_trim_sleep 0 | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_delete_sleep 0 | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_min_alloc_size 4K | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_prefer_deferred_size 0 | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_compression_min_blob_size 8K | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_compression_max_blob_size 64K | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_max_blob_size 64K | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_cache_size 3G | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_throttle_cost_per_io 4000 | tee -a $WORKSPACE/ceph-fio-config.log
        oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_deferred_batch_ops 16 | tee -a $WORKSPACE/ceph-fio-config.log

        echo "Dumping ceph configurartion after nvme/ssd enhancements" | tee -a $WORKSPACE/ceph-fio-config.log

        oc -n openshift-storage rsh $ceph_tools ceph config dump | tee -a $WORKSPACE/ceph-fio-config.log
}

##############  MAIN ################

set -e

retry_ocp_arg=
get_latest_ocs=false
nargs=$#
i=1
while (( $i<=$nargs ))
do
	arg=$1
	case "$arg" in
	--retry-ocp)
		retry_ocp_arg=--retry
		shift 1
		;;
	--latest-ocs)
		get_latest_ocs=true
		shift 1
		;;
	*)
		echo "Usage: $0 [ --retry-ocp ] [ --latest-ocs ]"
		echo
		echo "Use --retry when an error occurs while creating the ocp cluster."
		echo
		echo "For KVM, the existing VMs can be re-used.  Terraform will be re-invoked."
		echo "The default behaviour is to destroy the existing cluster."
		echo
		echo "For PowerVS, the retry attempts to re-use the existing LPARs which is"
		echo "the best option, because the alternative, cluster destroy, is not always"
		echo "successful for partially created clusters and the user must then"
		echo "manually delete cluster resources using the cloud GUI."
		echo
		echo "Use --latest-ocs to pull the latest commit from the ocsi-ci GH repo."
		echo
		echo "See the README for a description of required environment variables."
		exit 1
	esac
	(( i++ ))
done

if [ -z "$PLATFORM" ] || [ -z "$RHID_USERNAME" ] || [ -z "$RHID_PASSWORD" ]; then
	echo "Environment variables PLATFORM, RHID_USERNAME, RHID_PASSWORD must be set"
	exit 1
fi
if [ "$PLATFORM" == powervs ]; then
	if [ -z "$PVS_API_KEY" ] || [ -z "$PVS_SERVICE_INSTANCE_ID" ]; then
		echo "Environment variables PVS_API_KEY and PVS_SERVICE_INSTANCE_ID must be set for PowerVS"
		exit 1
	fi
	OCP_PROJECT=ocp4-upi-powervs
else
	OCP_PROJECT=ocp4-upi-kvm
fi


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

echo "Location of project: $WORKSPACE/ocs-upi-kvm"
echo "Location of log files: $WORKSPACE"

pushd $WORKSPACE/ocs-upi-kvm

if [ ! -e src/$OCP_PROJECT/var.tfvars ]; then
	echo "Refreshing submodule ${OCP_PROJECT}..."
	git submodule update --init src/$OCP_PROJECT
fi

if [ ! -e src/ocs-ci/README.md ]; then
	echo "Refreshing submodule ocs-ci..."
	git submodule update --init src/ocs-ci
fi

if [ "$get_latest_ocs" == true ]; then
	echo "Getting latest ocs-ci..."
	pushd $WORKSPACE/ocs-upi-kvm/src/ocs-ci
	git checkout master
	git pull
	popd
fi

echo "Invoking scripts..."

pushd $WORKSPACE/ocs-upi-kvm/scripts

set -o pipefail

./create-ocp.sh $retry_ocp_arg 2>&1 | tee $WORKSPACE/create-ocp.log

source $WORKSPACE/env-ocp.sh
oc get nodes 2>&1 | tee -a $WORKSPACE/create-ocp.log

./setup-ocs-ci.sh 2>&1 | tee $WORKSPACE/setup-ocs-ci.log

set +e
./deploy-ocs-ci.sh 2>&1 | tee $WORKSPACE/deploy-ocs-ci.log
CEPH_STATE=$(oc get cephcluster --namespace openshift-storage | tee -a $WORKSPACE/deploy-ocs-ci.log)
if [[ ! "$CEPH_STATE" =~ HEALTH_OK ]]; then
	echo "ERROR: Failed CEPH Health Check" | tee -a $WORKSPACE/deploy-ocs-ci.log
	oc get pods --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/deploy-ocs-ci.log
	exit 1
fi

config_ceph_for_nvmessd

set -e

./run-fio.sh block 2>&1 | tee $WORKSPACE/perf-fio-block.log

oc get cephcluster --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-block.log
oc get pods --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-block.log

sleep 1m

./run-fio.sh file 2>&1 | tee $WORKSPACE/perf-fio-file.log

oc get cephcluster --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-file.log
oc get pods --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-file.log
