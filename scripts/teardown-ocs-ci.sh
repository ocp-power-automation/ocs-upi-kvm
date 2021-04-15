#!/bin/bash

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

# If ocs-ci was run previously on the bastion, but this time it will be run locally
# on the new cluster, we try to clean the ocs state from the old cluster, before trying
# to remove the old cluster assuming destroy_ocp.sh assuming is called next.

if [[ "$OCS_CI_ON_BASTION" == true ]] || [[ -e $WORKSPACE/.ocs_ci_on_bastion ]]; then
	invoke_ocs_ci_on_bastion $0 $@
	rm -f $WORKSPACE/.ocs_ci_on_bastion
	exit $ocs_ci_on_bastion_rc
fi

set -e

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

source $WORKSPACE/venv/bin/activate		# enter 'deactivate' in venv shell to exit

run-ci -m deployment --teardown --cluster-name ocstest --cluster-path $WORKSPACE \
        --ocsci-conf conf/ocsci/production_powervs_upi.yaml \
        --ocsci-conf $WORKSPACE/ocs-ci-conf.yaml --collect-logs

deactivate

popd
