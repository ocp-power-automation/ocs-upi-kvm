#!/bin/bash

set -e

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

source $WORKSPACE/venv/bin/activate		# enter 'deactivate' in venv shell to exit

run-ci -m deployment --teardown --cluster-name ocstest --cluster-path $WORKSPACE \
        --ocsci-conf conf/ocsci/production_powervs_upi.yaml \
        --ocsci-conf $WORKSPACE/ocs-ci-conf.yaml --collect-logs

deactivate

popd
