#!/bin/bash

# These environments variables are required for PowerVS OCP cluster create

export PLATFORM=powervs # Supports powervs only
#export RHID_USERNAME=<your rh subscription id>
#export RHID_PASSWORD=<your rh subscription password>
export OCP_VERSION=${OCP_VERSION:=4.19} # 4.12-4.19 are supported
export OCS_VERSION=${OCS_VERSION:=4.19}
#export PVS_API_KEY=<your key>
#export FIPS_ENABLEMENT=false
# These are optional for PowerVS OCP cluster create.  Default values are shown

export CLUSTER_ID_PREFIX=${HOSTNAME:0:5}-${OCP_VERSION/./}
export PVS_SUBNET_NAME=ocp-net
#export SYSTEM_TYPE=s922
#export PROCESSOR_TYPE=shared
#export BASTION_IMAGE=rhel-92-05032023
#export USE_TIER1_STORAGE=false
#export OCS_CI_ON_BASTION=false

##############  MAIN ################

SERVICE_INSTANT_ID=( 1f6f0f7d-ced0-409c-95f0-170f9cb775c0       #syd
        fac4755e-8aff-45f5-8d5c-1d3b58b7a229       		#lon
	60e43366-08de-4287-8c42-b7942406efc9                    #tok
	73585ea1-0d40-4c0f-b97c-e3d6923aa153                    #mon
)

get_latest_ocs=false
nargs=$#
i=1
while (($i <= $nargs)); do
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
		;;
	esac
	((i++))
done

if [ -z "$RHID_USERNAME" ] || [ -z "$RHID_PASSWORD" ]; then
	echo "Environment variables RHID_USERNAME, RHID_PASSWORD must be set"
	exit 1
fi

if [ -z "$PVS_API_KEY" ]; then
	echo "Environment variables PVS_API_KEY must be set for PowerVS"
	exit 1
fi
OCP_PROJECT=ocp4-upi-powervs

# Set WORKSPACE where go code, binaries, and log files are placed

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

if [ -z "$LOGDIR" ] || [ ! -e "$LOGDIR" ]; then
	LOGDIR=$WORKSPACE/all-logs
	mkdir -p $LOGDIR
fi
if [ -z "$LOGDATE" ]; then
	LOGDATE=$(date "+%d%H%M")
fi

echo "Location of project: $WORKSPACE/ocs-upi-kvm"
echo "Location of log files: $WORKSPACE/logs-ocp"

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
	echo "Most recent commits to master:"
	git log --pretty=oneline | head -n 5
	popd
fi

pushd $WORKSPACE/ocs-upi-kvm/scripts

set -o pipefail
# Recreate the cluster for each test.  A failed test may compromise cluster health

for i in 1 2 4a 4b 4c 3; do
	case "$i" in
	1 | 2 | 4a)
		# These tier tests include add storage capacity tests which are implemented via an extra worker node
		export WORKERS=4
		;;
	*)
		unset WORKERS
		;;
	esac
	echo "Invoking tier $i test"
	# Try create cluster in lon,tok,mon,syd
	for j in ${SERVICE_INSTANT_ID[@]}; do
		success=0
		export PVS_SERVICE_INSTANCE_ID=$j
		source $WORKSPACE/ocs-upi-kvm/scripts/helper/powervs/parameters.sh
		echo "Invoking ./create-ocp.sh in $PVS_REGION" | tee -a $LOGDIR/create-ocp-$i-$PVS_REGION-$LOGDATE.log
		./create-ocp.sh 2>&1 | tee -a $LOGDIR/create-ocp-$i-$PVS_REGION-$LOGDATE.log
		if [ "$?" != 0 ]; then
			echo "Retrying ./create-ocp.sh in $PVS_REGION" | tee -a $LOGDIR/create-ocp-$i-$PVS_REGION-$LOGDATE.log
			sleep 5m
			./create-ocp.sh --retry 2>&1 | tee -a $LOGDIR/create-ocp-$i-$PVS_REGION-$LOGDATE.log

			if [ "$?" != 0 ]; then
				./destroy-ocp.sh | tee $LOGDIR/destroy-ocp-$i-$PVS_REGION-$LOGDATE.log
				if [ "$?" != 0 ]; then
					echo "ERROR: cluster destroy failed.  Use cloud GUI to remove virtual instances from $PVS_REGION" | tee -a $LOGDIR/destroy-ocp-$i-$PVS_REGION-$LOGDATE.log
				fi
				continue
			else
				echo "Cluster creation successful in $PVS_REGION"
				success=1
			fi
		else
			echo "Cluster creation successful in $PVS_REGION"
			success=1
		fi
		
		if [ $success == 1 ]; then
			source $WORKSPACE/env-ocp.sh
			oc get nodes -o wide 2>&1 | tee -a $LOGDIR/create-ocp-$i-$PVS_REGION-$LOGDATE.log
			./setup-ocs-ci.sh 2>&1 | tee $LOGDIR/setup-ocs-ci-$i-$PVS_REGION-$LOGDATE.log

			./deploy-ocs-ci.sh 2>&1 | tee $LOGDIR/deploy-ocs-ci-$i-$PVS_REGION-$LOGDATE.log
			CEPH_STATE=$(oc get cephcluster --namespace openshift-storage | tee -a $LOGDIR/deploy-ocs-ci-$i-$PVS_REGION-$LOGDATE.log)
			if [[ ! "$CEPH_STATE" =~ HEALTH_OK ]]; then
				echo "ERROR: Failed CEPH Health Check" | tee -a $LOGDIR/deploy-ocs-ci-$i-$PVS_REGION-$LOGDATE.log
				./destroy-ocp.sh --tier $i | tee $LOGDIR/destroy-ocp-$i-$PVS_REGION-$LOGDATE.log
				if [ "$?" != 0 ]; then
					echo "ERROR: cluster destroy failed.  Use cloud GUI to remove virtual instances"
				fi
				continue
			fi

			nohup ./test-ocs-ci.sh --tier $i 2>&1 >$LOGDIR/test-ocs-ci-$i-$PVS_REGION-$LOGDATE.log

			echo
			oc get cephcluster --namespace openshift-storage 2>&1 | tee -a $LOGDIR/test-ocs-ci-$i-$PVS_REGION-$LOGDATE.log
			echo
			oc get pods --namespace openshift-storage 2>&1 | tee -a $LOGDIR/test-ocs-ci-$i-$PVS_REGION-$LOGDATE.log

			./destroy-ocp.sh --tier $i | tee $LOGDIR/destroy-ocp-$i-$PVS_REGION-$LOGDATE.log
			if [ "$?" != 0 ]; then
				echo "ERROR: cluster destroy failed.  Use cloud GUI to remove virtual instances"
			fi
			break
		fi
	done
done
