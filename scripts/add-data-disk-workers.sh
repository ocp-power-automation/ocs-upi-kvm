#!/bin/bash

set -e

if [ ! -e helper/add-vdisk-workers.sh ]; then
	echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

set +e
notReady=$($WORKSPACE/bin/oc get nodes | grep ^worker | grep NotReady)
set -e
if [ -n "$notReady" ]; then
	echo "All worker nodes must be Ready"
	echo $notReady | grep NotReady
	exit 1
fi

# Data disk /dev/vdc is added by create_ocp.sh

export VDISK=${VDISK:="vdd"}

# Do not re-deploy VMs with huge pages as that is only done when the cluster is created

export ENABLE_HUGE_PAGES=false

sudo -sE helper/add-vdisk-workers.sh

$WORKSPACE/bin/oc get pv
