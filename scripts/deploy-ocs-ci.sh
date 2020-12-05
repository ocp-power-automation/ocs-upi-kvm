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

# Patch OCS-CI if a patch is available

if [ -e $WORKSPACE/ocs-upi-kvm/files/ocs-ci.patch ]; then

	set +e
	patch --dry-run -p1 < $WORKSPACE/ocs-upi-kvm/files/ocs-ci.patch
	rc=$?
	set -e

	if [ "$rc" == "0" ]; then
		echo "Patching ocs-ci/ocs/ripsaw.py to use alternative repo containing ppc64le images..."
		echo "This patch should be modified or removed as necessary to converge with ocs-ci"
		echo "--> $WORKSPACE/ocs-upi-kvm/files/ocs-ci.patch"
		patch -p1 < $WORKSPACE/ocs-upi-kvm/files/ocs-ci.patch
	else
		echo "WARNING: Failed to patch ocs-ci..."
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
