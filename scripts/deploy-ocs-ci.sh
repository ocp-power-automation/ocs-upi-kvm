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

# WORKAROUND for ocs-ci bug that downloads x86 binary

cp $WORKSPACE/bin/oc bin

mkdir -p data

cp $WORKSPACE/auth.yaml data/auth.yaml
cp $WORKSPACE/pull-secret.txt data/pull-secret

source $WORKSPACE/venv/bin/activate	# enter 'deactivate' in venv shell to exit

echo "Creating supplemental ocs-ci config - $WORKSPACE/ocs-ci-conf.yaml"

cp -f ../../files/ocs-ci-conf.yaml $WORKSPACE/ocs-ci-conf.yaml
export LOGDIR=$WORKSPACE/logs-ocs-ci/$OCP_VERSION
mkdir -p $LOGDIR
yq -y -i '.RUN.log_dir |= env.LOGDIR' $WORKSPACE/ocs-ci-conf.yaml

run-ci -m deployment --deploy \
	--ocs-version $OCS_VERSION --cluster-name=ocstest \
	--ocsci-conf=conf/ocsci/production_powervs_upi.yaml \
	--ocsci-conf=$WORKSPACE/ocs-ci-conf.yaml \
        --cluster-path=$WORKSPACE --collect-logs tests/

deactivate

popd
