#!/bin/bash

# This script may be relocated to the parent directory of ocs-upi-kvm project and
# edited to invoke a different sequence.  Sometimes to comment a line of execution
# to avoid recreating the cluster and other times to invoke ocs-ci with different
# parameters.  This script is relocatable, so the project itself is not modified.


# These environment variables are required for all platforms
###
# While looking how this works, I am doing what Sridhar asked.
# This branch MUST  be rejected after Sridhar look at it  and not merged
# Carlos
###
export PLATFORM=${PLATFORM:="kvm"}                              # Also supported: powervs.   Defaults to kvm

#export RHID_USERNAME=<your registered username>		# Change this line or preset in shell
#export RHID_PASSWORD=<your password>				# Edit or preset


# These environment variables are optional for all platforms

export OCP_VERSION=${OCP_VERSION:=4.7}                          # 4.5, 4.7, and 4.8 are also supported
export OCS_VERSION=${OCS_VERSION:=4.7}                          # 4.7 also


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
#export PVS_REGION=lon                                          # Or tok/tok04 sao/sao01 depending on service instance id
#export PVS_ZONE=lon06
#export SYSTEM_TYPE=s922
#export PROCESSOR_TYPE=shared
#export BASTION_IMAGE=rhel-83-02182021
#export USE_TIER1_STORAGE=false


# These are optional for PowerVS ocs-ci.  Default values are shown

#export OCS_CI_ON_BASTION=false                                 # When true, ocs-ci runs on bastion node, which may help
                                                                # with intermittent network issues and testcase timeouts

##############  MAIN ################

get_latest_ocs=false
nargs=$#
i=1
while (( $i<=$nargs ))
do
	arg=$1
	case "$arg" in
	--latest-ocs)
		get_latest_ocs=true
		shift 1
		;;
	*)
		echo "Usage: $0 [ --latest-ocs ]"
		echo
		echo "Use --latest-ocs to pull the latest commit from the ocsi-ci GH repo"
		echo
		echo "See README for description of required environment variables"
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

# Recreate the cluster for each test.  A failed test may compromise cluster health

for i in 1 2 4a 4b 4c 3
do
	./create-ocp.sh 2>&1 | tee $WORKSPACE/create-ocp-$i.log
	if [ "$?" != 0 ]; then
	       
		echo "Retrying ./create-ocp.sh" | tee -a $WORKSPACE/create-ocp-$i.log

		./create-ocp.sh --retry 2>&1 | tee -a $WORKSPACE/create-ocp-$i.log
		if [ "$?" != 0 ]; then

			./destroy-ocp.sh --tier $i | tee $WORKSPACE/destroy-ocp-$i.log
			if [ "$?" != 0 ] && [ "$PLATFORM" == powervs ]; then
				echo "ERROR: cluster destroy failed.  Use cloud GUI to remove virtual instances"
			fi
			continue
		fi
	fi

	source $WORKSPACE/env-ocp.sh
	oc get nodes -o wide 2>&1 | tee -a $WORKSPACE/create-ocp-$i.log

	./setup-ocs-ci.sh 2>&1 | tee $WORKSPACE/setup-ocs-ci-$i.log

	./deploy-ocs-ci.sh 2>&1 | tee $WORKSPACE/deploy-ocs-ci-$i.log
	CEPH_STATE=$(oc get cephcluster --namespace openshift-storage | tee -a $WORKSPACE/deploy-ocs-ci-$i.log)
	if [[ ! "$CEPH_STATE" =~ HEALTH_OK ]]; then

		echo "ERROR: Failed CEPH Health Check" | tee -a $WORKSPACE/deploy-ocs-ci-$i.log

		./destroy-ocp.sh --tier $i | tee $WORKSPACE/destroy-ocp-$i.log
		if [ "$?" != 0 ] && [ "$PLATFORM" == powervs ]; then
			echo "ERROR: cluster destroy failed.  Use cloud GUI to remove virtual instances"
		fi
		continue
	fi

	nohup ./test-ocs-ci.sh --tier $i 2>&1 > $WORKSPACE/test-ocs-ci-$i.log

	echo
	oc get cephcluster --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/test-ocs-ci-$i.log
	echo
	oc get pods --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/test-ocs-ci-$i.log

	./destroy-ocp.sh --tier $i | tee $WORKSPACE/destroy-ocp-$i.log
	if [ "$?" != 0 ] && [ "$PLATFORM" == powervs ]; then
		echo "ERROR: cluster destroy failed.  Use cloud GUI to remove virtual instances"
	fi
done

#nohup ./test-ocs-ci.sh --performance 2>&1 > $WORKSPACE/perf-ocs-ci.log
#nohup ./test-ocs-ci.sh --workloads 2>&1 > $WORKSPACE/workloads-ocs-ci.log
#nohup ./test-ocs-ci.sh --scale 2>&1 > $WORKSPACE/scale-ocs-ci.log
