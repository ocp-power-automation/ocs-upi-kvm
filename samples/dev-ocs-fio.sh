#!/bin/bash

# This script may be relocated to the parent directory of ocs-upi-kvm project and
# edited to invoke a different sequence.  Sometimes to comment a line of execution
# to avoid recreating the cluster and other times to invoke ocs-ci with different
# parameters.  This script is relocatable, so the project itself is not modified.


# These environment variables are required for all platforms

export PLATFORM=${PLATFORM:=powervs}                            # Only powervs and powervm (the latter implements PowerVC)

#export RHID_USERNAME=<your registered username>		# Change this line or preset in shell
#export RHID_PASSWORD=<your password>				# Edit or preset


# These environment variables are optional for all platforms

export OCP_VERSION=${OCP_VERSION:=4.16}                          # 4.5-4.16 are supported
export OCS_VERSION=${OCS_VERSION:=4.16}

# These are optional and apply only to kvm and powervs for now. They are presently ignored on powervm

export MASTER_DESIRED_CPU=1.5
export MASTER_DESIRED_MEM=48
export WORKER_DESIRED_CPU=6
export WORKER_DESIRED_MEM=96
#export FIPS_ENABLEMENT=false
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

#export CLUSTER_ID_PREFIX=$RHID_USERNAME                        # Actually first 3 chars of rhid_username + ocp version
#export PVS_SUBNET_NAME=ocp-net
#export PVS_REGION=lon  	                                # Or tok/tok04 sao/sao01 mon/mon01 depending on service instance id
#export PVS_ZONE=lon06
#export SYSTEM_TYPE=s922
#export PROCESSOR_TYPE=shared
#export BASTION_IMAGE=rhel-92-05032023
export WORKER_VOLUME_SIZE=768
export USE_TIER1_STORAGE=true


# These are required for PowerVC OCP cluster create

#export PVC_URL=<https://<HOSTNAME>:5000/v3>
#export PVC_LOGIN_NAME=<PVC email login>                        # IBM Intranet ID - name@us.ibm.com
#export PVC_LOGIN_PASSWORD=<password>                           # IBM Intranet Password      
#export PVC_TENANT=<PVC tenant>                                 # Below your username in PowerVC GUI
#export PVC_SUBNET_NAME=<PVC network>                           # PowerVC GUI--> Networks

# These are optional for PowerVC OCP cluster create

#export PVC_NETWORK_TYPE=SEA                                    # SRIOV also supported.  Check PVC GUI if enabled for PVC Network
#export PVC_HOST_GROUP=<a set of servers to target>


# These are optional and apply only to PowerVC and PowerVS cluster create.  Only PowerVC has shown a benefit from CMA in practice

#export CMA_PERCENT=8


# These are optional for PowerVC and PowerVS ocs-ci.  Default values are shown

#export OCS_CI_ON_BASTION=false                                 # When true, ocs-ci runs on bastion node
                                                                # May help with intermittent network problems and testcase timeouts

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
		echo "Use --retry-ocp when an error occurs while creating the ocp cluster."
		echo
		echo "For KVM, if the retry fails, one can destroy the cluster by invoking"
		echo "the destroy-ocp.sh script.  There is no manual cleanup required."
		echo
		echo "For PowerVS, the destroy operation is not always successful as the"
		echo "create operation may not have gotten far enough to generate build"
		echo "artifacts identifying the items to be destroyed.  In this case, one"
		echo "has to destroy the cluster manually using the Cloud GUI."
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
elif [ "$PLATFORM" == powervm ]; then
	OCP_PROJECT=ocp4-upi-powervm
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

function delete_pods () {
        echo "Deleting fio pods and pvcs..."

        sleep 5s

        oc get pod | grep ^fio | awk '{ print $1 }' | xargs oc delete pod
        oc get pvc | grep ^fio | awk '{ print $1 }' | xargs oc delete pvc

        exit
}
trap delete_pods SIGINT SIGTERM

./run-fio.sh block 2>&1 | tee $WORKSPACE/perf-fio-block.log

oc get cephcluster --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-block.log
oc get pods --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-block.log

sleep 1m

./run-fio.sh file 2>&1 | tee $WORKSPACE/perf-fio-file.log

oc get cephcluster --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-file.log
oc get pods --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-fio-file.log
