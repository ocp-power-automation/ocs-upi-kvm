#!/bin/bash

if [[ -z "$RHID_USERNAME" && -z "$RHID_PASSWORD" && -z "$RHID_ORG" && -z "$RHID_KEY" ]]; then
	echo "ERROR: Environment variables RHID_USERNAME and RHID_PASSWORD must both be set"
	echo "ERROR: OR"
	echo "ERROR: Environment variables RHID_ORG and RHID_KEY must both be set"
	exit 1
fi

if [[ -z "$RHID_USERNAME" && -n "$RHID_PASSWORD" ]] || [[ -n "$RHID_USERNAME" && -z "$RHID_PASSWORD" ]]; then
	echo "ERROR: Environment variables RHID_USERNAME and RHID_PASSWORD must both be set"
	exit 1
elif [[ -z "$RHID_ORG" && -n "$RHID_KEY" ]] || [[ -n "$RHID_ORG" && -z "$RHID_KEY" ]]; then
	echo "ERROR: Environment variables RHID_ORG and RHID_KEY must both be set"
	exit 1
fi

if [ ! -e helper/parameters.sh ]; then
	echo "ERROR: This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

set -e

source helper/parameters.sh

if [ ! -e $WORKSPACE/pull-secret.txt ]; then
	echo "ERROR: Missing $WORKSPACE/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
	exit 1
fi

echo "OCS_CI_ON_BASTION=$OCS_CI_ON_BASTION PLATFORM=$PLATFORM"

export PATH=$WORKSPACE/bin:$PATH

# The old cluster oc command and auth credentials are needed to destroy the old cluster

arg1=$1
helper/create-cluster.sh $arg1

# This is only invoked if create-cluster was successful

rm -f $WORKSPACE/.ocs_ci_on_bastion
rm -f $WORKSPACE/bin/oc
rm -rf $WORKSPACE/auth
rm -rf $WORKSPACE/metadata.json

setup_remote_oc_use

echo "Copying oc cmd from bastion to local host..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP:/usr/local/bin/oc $WORKSPACE/bin 2>/dev/null
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r root@$BASTION_IP:openstack-upi/auth $WORKSPACE 2>/dev/null
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r root@$BASTION_IP:openstack-upi/metadata.json $WORKSPACE 2>/dev/null

echo "export PATH=$WORKSPACE/bin/:$PATH" | tee $WORKSPACE/env-ocp.sh
echo "export KUBECONFIG=$WORKSPACE/auth/kubeconfig" | tee -a $WORKSPACE/env-ocp.sh
chmod a+x $WORKSPACE/env-ocp.sh

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

if [ "$PLATFORM" == kvm ]; then
	export VDISK=vdc
	sudo -sE helper/kvm/add-vdisk-workers.sh
fi

helper/check-health-cluster.sh

if (( CMA_PERCENT > 0 )); then

	# TODO Adapt to powervm.  Generate compute templates from WORKER_DESIRED_MEM

	if [ "$PLATFORM" == powervs ]; then
		KARG_CMA=$(( WORKER_DESIRED_MEM * CMA_PERCENT / 100 ))
	else
		KARG_CMA=5				# Masters have 32GBs and workers 64GBs presently
	fi

	if (( KARG_CMA > 0 )); then
		export KARG_CMA=${KARG_CMA}G
		cat ../files/rhcos-kargs/05-worker-kernelarg-cma.yaml.in | envsubst > $WORKSPACE/05-worker-kernelarg-cma.yaml
		oc create -f $WORKSPACE/05-worker-kernelarg-cma.yaml

		(( delay = BOOT_DELAY_PER_WORKER * WORKERS ))
		echo "Delaying $delay minutes for worker nodes to reboot...  New kernel boot argument: slub_max_order=0 cma=$KARG_CMA"
		sleep ${delay}m

		helper/check-health-cluster.sh
	fi
fi

echo ""
echo "To access the cluster:"
echo "source $WORKSPACE/env-ocp.sh"
echo "oc get nodes -o wide"
