#!/bin/bash

user=$(whoami)
if [ "$user" != root ]; then
	echo "This script must be invoked as root"
	exit 1
fi

if [ ! -d helper ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

if [[ -z "$RHID_USERNAME" ]] || [[ -z "$RHID_PASSWORD" ]]; then
	echo "Environment variables RHID_USERNAME and RHID_PASSWORD must both be set"
	exit 1
fi

if [ ! -e ~/pull-secret.txt ]; then
        echo "Missing ~/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
        exit 1
fi

export OCP_VERSION=${OCP_VERSION:=4.5}
export WORKERS=${WORKERS:=3}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="65536"}
export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="16"}

source helper/parameters.sh

set -xe

retry=false
if [ "$1" == "--retry" ]; then
	retry=true
fi

# Remove known_hosts before creating a new cluster to ensure there is
# no SSH conflict arising from previously clusters

if [[ -d ~/.ssh ]] && [[ "$retry" == false ]]; then
	rm -f ~/.ssh/known_hosts
fi

# Setup kvm on the host

if [ ! -e ~/.kvm_setup ]; then
	helper/setup-kvm-host.sh
	touch ~/.kvm_setup
elif [ "$retry" == false ]; then
	helper/virsh-cleanup.sh
fi

helper/create-cluster.sh $1

scp -o StrictHostKeyChecking=no root@192.168.88.2:/usr/local/bin/oc /usr/local/bin
scp -o StrictHostKeyChecking=no -r root@192.168.88.2:openstack-upi/auth ~

export KUBECONFIG=~/auth/kubeconfig

helper/add-data-disks.sh
