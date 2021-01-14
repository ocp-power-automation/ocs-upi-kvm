#!/bin/bash

set -e

if [ ! -e helper/parameters.sh ]; then
	echo "ERROR: This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

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

# This script creates an ocp cluster for OCS CI which expects ntp servers for all platforms

export CHRONY_CONFIG=${CHRONY_CONFIG:="true"}
export WORKERS=${WORKERS:=3}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="65536"}
export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="16"}

source helper/parameters.sh

if [ ! -e $WORKSPACE/pull-secret.txt ]; then
	echo "ERROR: Missing $WORKSPACE/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
	exit 1
fi

arg1=$1
retry=false
if [ "$1" == "--retry" ]; then
	retry_version=$(sudo virsh list | grep bastion | awk '{print $2}' | sed 's/4-/4./' | sed 's/-/ /g' | awk '{print $2}' | sed 's/ocp//')
	if [ "$retry_version" != "$OCP_VERSION" ]; then
		echo "WARNING: Ignoring --retry argument.  existing version:$retry_version  requested version:$OCP_VERSION"
		retry=false
		unset arg1
	else
		retry=true
	fi
fi

if [ ! -e $WORKSPACE/$BASTION_IMAGE ]; then
	file_present $IMAGES_PATH/$BASTION_IMAGE
	if  [[ "$file_rc" != 0 ]]; then
		echo "ERROR: Missing $BASTION_IMAGE.  Get it from https://access.redhat.com/downloads/content/479/ and prepare it per README"
		exit 1
	fi
fi

# Remove known_hosts before creating a new cluster to ensure there is
# no SSH conflict arising from previously clusters

if [[ -d ~/.ssh ]] && [[ "$retry" == false ]]; then
	rm -f ~/.ssh/known_hosts
fi

# Setup kvm on the host

invoke_kvm_setup=false
if [ ! -e ~/.kvm_setup ]; then
	invoke_kvm_setup=true
else
	source ~/.kvm_setup
	if [[ -z "$KVM_SETUP_GENCNT_INSTALLED" ]] || [[ "$KVM_SETUP_GENCNT_INSTALLED" -lt "$KVM_SETUP_GENCNT" ]]; then
		invoke_kvm_setup=true
	fi
fi

if [ "$invoke_kvm_setup" == "true" ]; then
	echo "Invoking setup-kvm-host.sh"
	sudo -sE helper/setup-kvm-host.sh
	echo "KVM_SETUP_GENCNT_INSTALLED=$KVM_SETUP_GENCNT" > ~/.kvm_setup
fi

# Remove pre-existing clusters

if [ "$retry" == false ]; then
	echo "Invoking virsh-cleanup.sh"
	sudo -sE helper/virsh-cleanup.sh
fi

# Validate after VMs are they are destroyed and hugepages freed

enable_hugepages

echo "export PATH=$WORKSPACE/bin/:$PATH" | tee $WORKSPACE/env-ocp.sh
chmod a+x $WORKSPACE/env-ocp.sh

export PATH=$WORKSPACE/bin:$PATH

helper/create-cluster.sh $arg1

rm -f $WORKSPACE/bin/oc
rm -rf $WORKSPACE/auth

scp -o StrictHostKeyChecking=no root@192.168.88.2:/usr/local/bin/oc $WORKSPACE/bin
scp -o StrictHostKeyChecking=no -r root@192.168.88.2:openstack-upi/auth $WORKSPACE

echo "export KUBECONFIG=$WORKSPACE/auth/kubeconfig" | tee -a $WORKSPACE/env-ocp.sh

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

export VDISK=vdc
sudo -sE helper/add-vdisk-workers.sh

sudo -sE helper/check-health-cluster.sh

echo ""
echo "To access the cluster:"
echo "source $WORKSPACE/env-ocp.sh"
echo "oc get nodes -o wide"
