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

set -e

export OCS_VERSION=${OCS_VERSION:=4.6}
export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

patchfiles=(../../files/ocs-ci/ocs-ci-[0-9][0-9]-*.patch)

kvm_present=$(/usr/sbin/lsmod | grep kvm)
if [ -n "$kvm_present" ]; then
	platform=kvm
else
	platform=powervs
fi

platform_patchfiles=(../../files/ocs-ci/$platform/ocs-ci-*[0-9][0-9]-*.patch)

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
	patch --dry-run -p1 < $WORKSPACE/ocs-ci.patch
	rc=$?
	set -e

	if [ "$rc" == "0" ]; then
		echo "Patching ocs-ci..."
		patch -p1 < $WORKSPACE/ocs-ci.patch
	else
		echo "WARNING: Failed to patch ocs-ci.  Has git submodule ocs-ci HEAD changed?"
	fi
fi

# WORKAROUND for ocs-ci bug that downloads x86 binary

cp -f $WORKSPACE/bin/oc bin

mkdir -p data

cp $WORKSPACE/auth.yaml data/auth.yaml
cp $WORKSPACE/pull-secret.txt data/pull-secret

source $WORKSPACE/venv/bin/activate	# enter 'deactivate' in venv shell to exit

echo "Creating supplemental ocs-ci config - $WORKSPACE/ocs-ci-conf.yaml"

export LOGDIR=$WORKSPACE/logs-ocs-ci/$OCP_VERSION

cp -f ../../files/ocs-ci-conf.yaml $WORKSPACE/ocs-ci-conf.yaml
mkdir -p $LOGDIR
yq -y -i '.RUN.log_dir |= env.LOGDIR' $WORKSPACE/ocs-ci-conf.yaml

run-ci -m deployment --deploy \
	--ocs-version $OCS_VERSION --cluster-name ocstest \
	--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
	--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
        --cluster-path $WORKSPACE --collect-logs tests/

deactivate

popd
