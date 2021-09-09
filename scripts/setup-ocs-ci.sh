#!/bin/bash

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

if [ ! -e $WORKSPACE/pull-secret.txt ]; then
	echo "Missing $WORKSPACE/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
	exit 1
fi

if [ ! -e $WORKSPACE/auth.yaml ]; then
	echo "$WORKSPACE/auth.yaml is required"
	exit 1
fi

if [ "$OCS_CI_ON_BASTION" == true ]; then
	setup_remote_ocsci_use			# Copy pull-secret.txt, auth.yaml, and ocs-upi-kvm to bastion
	invoke_ocs_ci_on_bastion $0 $@
	exit $ocs_ci_on_bastion_rc
fi

sudo yum -y install libffi-devel lapack atlas-devel openssl-devel gcc gcc-c++ gcc-gfortran make patch
sudo yum -y install python38-devel python38-setuptools python3-virtualenv python3-docutils rust-toolset
sudo yum -y install curl libcurl-devel unzip libxml2-devel

pushd ../src/ocs-ci

set +e

patchfiles=( $(ls ../../files/ocs-ci/ocs-ci-[0-9][0-9]-*.patch) )
echo "patchfiles=${patchfiles[@]}"

platform_patchfiles=( $(ls ../../files/ocs-ci/$PLATFORM/ocs-ci-*[0-9][0-9]-*.patch) )
echo platform_patchfiles=${platform_patchfiles[@]}

set -e

# Patch OCS-CI if a patch is available

if [[ "${#patchfiles[@]}" -gt 0 ]] || [[ "${#platform_patchfiles[@]}" -gt 0 ]]; then

        echo "Generating consolidated patch file $WORKSPACE/ocs-ci.patch from $WORKSPACE/ocs-upi-kvm/files/ocs-ci/"
        > $WORKSPACE/ocs-ci.patch
        if [[ "${#patchfiles[@]}" -gt 0 ]]; then
                cat "${patchfiles[@]}" >> $WORKSPACE/ocs-ci.patch
        fi
        if [[ "${#platform_patchfiles[@]}" -gt 0 ]]; then
                cat "${platform_patchfiles[@]}" >> $WORKSPACE/ocs-ci.patch
        fi

        set +e
        patch --dry-run -f -p1 < $WORKSPACE/ocs-ci.patch
        rc=$?
        set -e

        if [ "$rc" == "0" ]; then
                echo "Patching ocs-ci..."
                patch -p1 < $WORKSPACE/ocs-ci.patch
        else
                echo "WARNING: Failed to patch ocs-ci.  Has git submodule ocs-ci HEAD changed?"
        fi
fi

rm -rf $WORKSPACE/venv

python3.8 -m venv $WORKSPACE/venv

source $WORKSPACE/venv/bin/activate		# activate named python venv

pip3 install --upgrade pip setuptools wheel
pip3 install -r requirements.txt
pip3 install yq
pip3 install boto3

deactivate					# exit venv shell

popd
