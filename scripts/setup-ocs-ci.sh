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
     # Update package index
    sudo apt-get update -o Acquire::Retries=5
else
    sudo dnf update -y
    sudo dnf -y install \
        gcc gcc-c++ gcc-gfortran make patch \
        libffi-devel lapack atlas-devel \
        openssl-devel curl libcurl-devel \
        libxml2-devel unzip rust-toolset
    #Needed for pyyaml
    subscription-manager repos --enable codeready-builder-for-rhel-9-ppc64le-rpms
    dnf install -y libyaml-devel
    # Add EPEL repo if not already installed
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm || true
    # Install Python 3.11
    sudo dnf install -y python3.11 python3.11-devel python3.11-pip
    #Install Openblas
    sudo dnf install -y openblas openblas-devel
	#Install kustomize
    curl -fL -o /tmp/kustomize.tar.gz \
https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v5.8.1/kustomize_v5.8.1_linux_ppc64le.tar.gz
    tar -xzf /tmp/kustomize.tar.gz -C /tmp

    sudo mv /tmp/kustomize /usr/local/bin/kustomize
    sudo chmod +x /usr/local/bin/kustomize

    kustomize version
fi

pushd "$WORKSPACE/ocs-upi-kvm/src/ocs-ci"

set +e


FILES_DIR="$WORKSPACE/ocs-upi-kvm/files/ocs-ci"

# Collect patch files safely
patchfiles=( $FILES_DIR/ocs-ci-[0-9][0-9]-*.patch )
[ -e "${patchfiles[0]}" ] || patchfiles=()

platform_patchfiles=( $FILES_DIR/$PLATFORM/ocs-ci-*[0-9][0-9]-*.patch )
[ -e "${platform_patchfiles[0]}" ] || platform_patchfiles=()

echo "patchfiles=${patchfiles[@]}"
echo "platform_patchfiles=${platform_patchfiles[@]}"


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

rm -rf "$WORKSPACE/venv"
PYTHON_BIN=$(command -v python3.11 || command -v python3)
"$PYTHON_BIN" -m venv "$WORKSPACE/venv"

. "$WORKSPACE/venv/bin/activate"		# activate named python venv

pip3 install --upgrade pip setuptools wheel Cython
pip3 install -r requirements.txt 
pip3 install yq
pip3 install pytest-html-merger

deactivate					# exit venv shell

popd
