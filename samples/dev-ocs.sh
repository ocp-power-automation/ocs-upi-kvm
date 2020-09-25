#!/bin/bash

set -e

arg1=$1
if [[ -n "$arg1" ]] && [[ "$arg1" != --retry ]]; then
	echo "Invalid argument - $arg1"
	echo "Usage: $0 [ --retry ]"
	echo ""
	echo "Use --retry when an error occurs while creating the ocp cluster."
	echo "In this case, the existing VMs are reused and terraform is re-invoked."
	echo "If the error persists, don't specify --retry.  The default behaviour"
	echo "is to destroy the existing cluster and then create a new one."
	exit 1
fi

# Edit username and password below or specify them via the command line

if [ -z "$RHID_USERNAME" ]; then
	export RHID_USERNAME=
fi
if [ -z "$RHID_PASSWORD" ]; then
	export RHID_PASSWORD=
fi

#export OCP_VERSION=4.6 			# 4.5 is default.  4.4 and 4.6 also supported

#export WORKERS=5				# Default is 3 

# This image is obtained from RedHat Customer Portal and must be prepared for use

#export BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}

# Controls file placement of VM boot images

#export IMAGES_PATH=/var/lib/libvirt/images	# Set to file system with the most space 

# Ensure ocs-ci is at latest commit

pushd ~/ocs-upi-kvm/src/ocs-ci

git checkout master
git pull

pushd ~/ocs-upi-kvm/scripts

./create-ocp.sh $arg1
./setup-ocs-cicd.sh
./run-ocs-cicd.sh
