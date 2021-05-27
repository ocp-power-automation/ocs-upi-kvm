#!/bin/bash

# This script may be relocated to the parent directory of the ocs-upi-kvm project
# and edited to invoke different sequences and/or to input credentials without
# having to modify the project.
#
# The E2E performance test sequence is different from other automation test
# scripts in this project.  OCS_CI_ON_BASTION must be set to true as the
# ocs-ci performance suite accesses the service elasticserch via an IP Address.
# An IP route is added to the bastion node to facilitate this connection.
#
# The E2E flow for ocs-ci performance test is:
#
# 1.  Create ocp cluster from the remote host.  Bastion IP Addr is located in $WORKSPACE/.bastion_ip
# 2.  Setup ocs-ci on the bastion node and deploy ocs.  OCS_CI_ON_BASTION=true triggers remote operations
# 3.  From remote host, elasticsearch service.  This utilizes oc command only
# 4.  Setup an IP route on the bastion node to the OCP service network via ssh root@$BASTION_IP
# 5.  Relocate this script to bastion node via scp root@$BASTION_IP
# 6.  Remotely invoke dev-ocs-perf.sh --run-perf on the bastion node via ssh
# 7.  Remotely copy ocs-ci perf logs from bastion via scp
# 8.  Destroy elasticsearch and remove route

export OCS_CI_ON_BASTION=true                                   # This must be set to true

# These environment variables are required for all platforms

export PLATFORM=powervs                                         # This must be set to powervs

#export RHID_USERNAME=<your registered username>		# Change this line or preset in shell
#export RHID_PASSWORD=<your password>				# Edit or preset


# These environment variables are optional for all platforms

export OCP_VERSION=${OCP_VERSION:=4.7}                          # 4.5, 4.7, and 4.8 are also supported
export OCS_VERSION=${OCS_VERSION:=4.7}

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
#export BASTION_IMAGE=rhel-83-02182021
#export WORKER_VOLUME_SIZE=500
#export USE_TIER1_STORAGE=false

# These are optional for PowerVS ocs-ci.  Default values are shown

#export CMA_PERCENT=8

##############  MAIN ################

set -e

function perf_test () {

	export WORKSPACE=~
	pushd $WORKSPACE/ocs-upi-kvm/src/ocs-ci

	export ES_CLUSTER_IP=$(oc get service elasticsearch -n elastic | grep ^elasticsearch | awk '{print $3}')
	if [ -z "$ES_CLUSTER_IP" ]; then
		echo "Elasticsearch is required for this test"
		exit 1
	fi

	source $WORKSPACE/venv/bin/activate             # enter 'deactivate' in venv shell to exit

	yq -y -i '.PERF.production_es |= false' $WORKSPACE/ocs-ci-conf.yaml
	yq -y -i '.PERF.deploy_internal_es |= false' $WORKSPACE/ocs-ci-conf.yaml
	yq -y -i '.PERF.internal_es_server |= env.ES_CLUSTER_IP' $WORKSPACE/ocs-ci-conf.yaml

	# The 'tests/e2e/...' can be obtained from the html report of performance, workloads, tier tests, ...

	run-ci -m "performance" --cluster-name ocstest --cluster-path $WORKSPACE \
		--ocp-version $OCP_VERSION --ocs-version=$OCS_VERSION \
		--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
		--ocsci-conf conf/ocsci/lso_enable_rotational_disks.yaml \
		--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
		--collect-logs \
		tests/e2e/performance/test_fio_benchmark.py::TestFIOBenchmark::test_fio_workload_simple[CephBlockPool-random] 2>&1 | tee $WORKSPACE/test-fio.log

	deactivate
}

cwdir=$(pwd)
cmdpath=$(dirname $0)
cmd=$0

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
	--run-test)
		perf_test
		exit
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
	pushd src/ocs-ci
	git fetch origin pull/4127/head:avi
	git checkout avi
fi

#if [ "$get_latest_ocs" == true ]; then
#	echo "Getting latest ocs-ci..."
#	pushd $WORKSPACE/ocs-upi-kvm/src/ocs-ci
#	git checkout master
#	git pull
#	popd
#fi


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
set -e

function delete_elasticsearch () {
        echo "Deleting elasticsearch..."

	set +e
	oc delete deployments.apps/elasticsearch -n elastic
	oc delete route/elasticsearch -n elastic
	oc delete service/elasticsearch -n elastic
	oc delete project/elastic
	if [ -n "$BASTION_IP" ]; then
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP ip route del $service_cidr via $master0_ip
	fi

        exit
}

trap delete_elasticsearch SIGINT SIGTERM

oc new-project elastic
oc new-app quay.io/piyushgupta1551/elasticsearch:7.11
oc expose service/elasticsearch
oc project default

export ES_CLUSTER_IP=$(oc get service elasticsearch -n elastic | grep ^elasticsearch | awk '{print $3}')
if [ -z "$ES_CLUSTER_IP" ]; then
	echo "ES_CLUSTER_IP is not set"
	delete_elasticsearch
	exit 1
fi

# The cluster IP is visible only inside the cluster.  Add route to bastion node for the ocp service network

service_cidr=$(oc get networks.config/cluster -o jsonpath='{$.status.serviceNetwork}')
service_cidr=${service_cidr//\"/}
service_cidr=${service_cidr/[/}
service_cidr=${service_cidr/]/}
node_cidr="192.168.0.0\/24"
master0_ip=$(oc get node/master-0 -o wide | tail -1 | awk '{print $6}')

source $WORKSPACE/.bastion_ip

set -x

netdev=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP ip r | grep $node_cidr | head -n 1 | awk '{print $3}')
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP ip route add $service_cidr via $master0_ip dev $netdev onlink | tee $WORKSPACE/perf-ocs-ci.log

echo "Relocating this script..."

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $cwdir/$cmd root@$BASTION_IP: | tee -a $WORKSPACE/perf-ocs-ci.log

echo "Remotely invoking this script..."

cmdname=$(echo $cmd | sed "s|$cmdpath/||")
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP ./$cmdname --run-test | tee -a $WORKSPACE/perf-ocs-ci.log

echo "Getting the test logs..."

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p -r root@$BASTION_IP:logs-ocs-ci $WORKSPACE | tee $WORKSPACE/perf-ocs-ci.log

set +x

oc get cephcluster --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-ocs-ci.log
oc get pods --namespace openshift-storage 2>&1 | tee -a $WORKSPACE/perf-ocs-ci.log

delete_elasticsearch
