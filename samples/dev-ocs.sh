#!/bin/bash

# If arg1 is set to --retry, then cluster create will invoke terraform apply
# again without tearing down the existing cluster.

set -e

export RHID_USERNAME=lbrownin
#export RHID_PASSWORD=

#export OCP_VERSION=4.5 			# 4.5 is default.  4.4 and 4.6 also supported

#export WORKERS=3				# Default is 3 

# Controls file placement of VM boot images

export IMAGES_PATH=/var/lib/libvirt/images

# Ensure ocs-ci is at latest commit

pushd ~/ocs-upi-kvm/src/ocs-ci

git checkout master
git fetch

pushd ~/ocs-upi-kvm/scripts

./create-ocp.sh $1				# --retry only, skips cluster destroy and re-invokes terraform
./setup-ocs-cicd.sh
./run-ocs-cicd.sh
