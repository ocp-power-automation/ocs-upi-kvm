#!/bin/bash

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

if [ "$OCS_CI_ON_BASTION" == true ]; then
	invoke_ocs_ci_on_bastion $0 $@
	if [ "$ocs_ci_on_bastion_rc" == 0 ]; then
		touch $WORKSPACE/.ocs_ci_on_bastion
	fi
	exit $ocs_ci_on_bastion_rc
fi

if [ ! -e $WORKSPACE/pull-secret.txt ]; then
	echo "Missing $WORKSPACE/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
	exit 1
fi

if [ ! -e $WORKSPACE/auth.yaml ]; then
	echo "$WORKSPACE/auth.yaml is required"
	exit 1
fi

set -e

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

# This script provides DR capabilties implemented by ocp4-upi-powervs

if [ -e ../../files/ocs-ci/$PLATFORM/ocpdr ]; then
	cp -f ../../files/ocs-ci/$PLATFORM/ocpdr bin
fi

# WORKAROUND for ocs-ci bug that downloads x86 binary

cp -f $WORKSPACE/bin/oc bin

mkdir -p data

# This tar file patches the esdumper pod in elastic-system project for performance suite

if [ -e ../../files/ocs-ci/esdumper.tar ]; then
        cp -f ../../files/ocs-ci/esdumper.tar data
fi

cp $WORKSPACE/auth.yaml data/auth.yaml
cp $WORKSPACE/pull-secret.txt data/pull-secret

source $WORKSPACE/venv/bin/activate	# enter 'deactivate' in venv shell to exit

echo "Creating supplemental ocs-ci config - $WORKSPACE/ocs-ci-conf.yaml"

export LOGDIR=$WORKSPACE/logs-ocs-ci/$OCS_VERSION
mkdir -p $LOGDIR
cp -f ../../files/ocs-ci/ocs-ci-conf.yaml $WORKSPACE/ocs-ci-conf.yaml
update_supplemental_ocsci_config

echo "run-ci -m deployment --deploy --ocs-version $OCS_VERSION ..."

run-ci -m deployment --deploy \
	--ocs-version $OCS_VERSION --cluster-name ocstest \
	--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
	--ocsci-conf conf/ocsci/lso_enable_rotational_disks.yaml \
	--ocsci-conf conf/ocsci/manual_subscription_plan_approval.yaml \
	--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
        --cluster-path $WORKSPACE --collect-logs tests/

deactivate

popd
