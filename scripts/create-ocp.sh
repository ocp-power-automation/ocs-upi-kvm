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

set -xe

# These variable should be set in the jenkins script

#export RHID_USERNAME=
#export RHID_PASSWORD=

# These variables may be used to override the default boot 
# and data disk sizes.  Defaults are shown below

#export DATA_DISK_SIZE=${DATA_DISK_SIZE:=100}		# in GBs
#export BOOT_DISK_SIZE=${BOOT_DISK_SIZE:=32}		# in GBs

# This variable identifies the path where virsh will allocate
# qemu/libvirt objects.  It should be set to the filesystem with the
# most free space.  If /home has the most free space, then this
# variable should be set to /home/libvirt/images 

#export IMAGES_PATH=${IMAGES_PATH:="/var/lib/libvirt/images"}

# These settings reflect OCS requirements wrt OCP

export OCP_VERSION=${OCP_VERSION:=4.5}
export WORKERS=${WORKERS:=3}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="65536"}
export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="16"}

# Additional settings may be found in scripts/helper/parameters.sh

# Remove known_hosts before creating a new cluster to ensure there is
# no SSH conflict arising from previously clusters

if [ -d ~/.ssh ]; then
	rm -f ~/.ssh/known_hosts
fi

# Setup kvm on the host

if [ ! -e ~/.kvm_setup ]; then
	helper/setup-kvm-host.sh
	touch ~/.kvm_setup
else
	helper/virsh-cleanup.sh
fi

helper/create-cluster.sh

scp -o StrictHostKeyChecking=no root@192.168.88.2:/usr/local/bin/oc /usr/local/bin
scp -o StrictHostKeyChecking=no -r root@192.168.88.2:openstack-upi/auth ~

# add-data-disk.sh should be run before grow-boot-disk.sh, because the latter
# reboots the VM to resize the root file system after the underlying qcow2 image
# in the host has been expanded.  There is no dynamic reconfiguration capability
# of base devices in VMs, so the VM must be rebooted for the new data disk to be
# recognized and configured by RHCOS in the VM.  In effect, add data disk piggy
# backs on reboot operation in grow boot disk.

export KUBECONFIG=~/auth/kubeconfig

set -x

helper/add-data-disks.sh

helper/grow-boot-disks.sh

