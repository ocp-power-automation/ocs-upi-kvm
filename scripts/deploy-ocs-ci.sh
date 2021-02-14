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

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

# WORKAROUND for ocs-ci bug that downloads x86 binary

cp -f $WORKSPACE/bin/oc bin

mkdir -p data

cp $WORKSPACE/auth.yaml data/auth.yaml
cp $WORKSPACE/pull-secret.txt data/pull-secret

source $WORKSPACE/venv/bin/activate	# enter 'deactivate' in venv shell to exit

echo "Creating supplemental ocs-ci config - $WORKSPACE/ocs-ci-conf.yaml"

cp -f ../../files/ocs-ci-conf.yaml $WORKSPACE/ocs-ci-conf.yaml

export LOGDIR=$WORKSPACE/logs-ocs-ci/$OCS_VERSION
mkdir -p $LOGDIR
yq -y -i '.RUN.log_dir |= env.LOGDIR' $WORKSPACE/ocs-ci-conf.yaml
yq -y -i '.DEPLOYMENT.ocs_registry_image |= env.OCS_REGISTRY_IMAGE' $WORKSPACE/ocs-ci-conf.yaml

export ocp_must_gather=quay.io/rhceph-dev/ocs-must-gather:latest-$OCS_VERSION
yq -y -i '.REPORTING.ocp_must_gather_image |= env.ocp_must_gather' $WORKSPACE/ocs-ci-conf.yaml

if [ "$PLATFORM" == powervs ]; then
	yq -y -i '.ENV_DATA.number_of_storage_disks = 8' $WORKSPACE/ocs-ci-conf.yaml
fi

echo "run-ci -m deployment --deploy -ocs-version $OCS_VERSION ..."

run-ci -m deployment --deploy \
	--ocs-version $OCS_VERSION --cluster-name ocstest \
	--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
	--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
        --cluster-path $WORKSPACE --collect-logs tests/

deactivate

popd
