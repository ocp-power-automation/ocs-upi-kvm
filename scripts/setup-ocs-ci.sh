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
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP "ls -l ~/go/bin/kustomize"
        if [ $? != 0 ]
        then
                scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/ocs-upi-kvm/scripts/helper/kustomize.sh root@$BASTION_IP: >/dev/null 2>&1
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP chmod 0755 kustomize.sh >/dev/null 2>&1
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP ./kustomize.sh >/dev/null 2>&1
        fi
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP "ls -l ~/vault"
        if [[ $? != 0 && "$VAULT_SUPPORT" == true ]]; then
                scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/ocs-upi-kvm/scripts/helper/vault-setup.sh root@$BASTION_IP: >/dev/null 2>&1
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP chmod 0755 vault-setup.sh >/dev/null 2>&1
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP ./vault-setup.sh >/dev/null 2>&1
        fi
	invoke_ocs_ci_on_bastion $0 $@
	exit $ocs_ci_on_bastion_rc
fi

if [  -n "$(uname -a | grep Ubuntu)" ]; then
	sudo apt update
	sudo apt install libffi-dev liblapack3 libatlas-base-dev libssl-dev gcc g++ gfortran make patch python3-venv libcurl4-openssl-dev libssl-dev libxml2-dev libxslt1-dev -y
else
	sudo dnf -y install libffi-devel lapack atlas-devel openssl-devel gcc gcc-c++ gcc-gfortran make patch
  sudo dnf -y install python3-devel python3-setuptools  rust-toolset
  sudo dnf -y install curl libcurl-devel unzip libxml2-devel
fi
git clone https://github.com/OpenMathLib/OpenBLAS.git
cd OpenBLAS
git checkout v0.3.26
make -j8
make PREFIX=/usr/local/OpenBLAS install
export PKG_CONFIG_PATH=/usr/local/OpenBLAS/lib/pkgconfig
cd ..

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

python3.9 -m venv $WORKSPACE/venv

. $WORKSPACE/venv/bin/activate		# activate named python venv

pip3 install --upgrade pip setuptools wheel Cython
pip3 install -r requirements.txt 
pip3 install yq
pip3 install boto3
pip3 install pytest-html-merger

deactivate					# exit venv shell

popd
