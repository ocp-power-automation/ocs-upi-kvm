#!/bin/bash

# This script assumes OCS is already deployed using ocs-upi-kvm project.
# Document for Upgrding : https://github.com/red-hat-storage/ocs-ci/blob/master/docs/upgrade.md#upgrade-execution
# These environment variables are necessary to upgrade OCS
 
# export OCS_VERSION=4.7
# export UPGRADE_OCS_VERSION=4.7.1   # For upgrading OCS CSV version from 4.7.0 to 4.7.1 
# export UPGRADE_OCS_REGISTRY=<rhceph-dev image for 4.7.1 version>

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

if [ "$OCS_CI_ON_BASTION" == true ]; then
	invoke_ocs_ci_on_bastion $0 $@
	exit $ocs_ci_on_bastion_rc
fi

set -e

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

source $WORKSPACE/venv/bin/activate		# enter 'deactivate' in venv shell to exit

echo "Invoking run-ci command for upgrade..."

run-ci -m "pre_upgrade or ocs_upgrade or post_upgrade" --ocs-version $OCS_VERSION \
        --upgrade-ocs-version $UPGRADE_OCS_VERSION --upgrade-ocs-registry-image "'$UPGRADE_OCS_REGISTRY'" \
        --ocsci-conf conf/ocsci/production_powervs_upi.yaml \
        --ocsci-conf conf/ocsci/lso_enable_rotational_disks.yaml \
        --ocsci-conf conf/ocsci/manual_subscription_plan_approval.yaml \
        --ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
        --cluster-name ocstest --cluster-path $WORKSPACE \
        --collect-logs tests/ 2>&1 | tee $WORKSPACE/upgrade-ocs-$UPGRADE_OCS_VERSION.log

echo -e "\n After Upgrading..." >> $WORKSPACE/upgrade-ocs-$UPGRADE_OCS_VERSION.log

oc get csv -n openshift-storage 2>&1 | tee -a $WORKSPACE/upgrade-ocs-$UPGRADE_OCS_VERSION.log
oc get pods -n openshift-storage 2>&1 | tee -a $WORKSPACE/upgrade-ocs-$UPGRADE_OCS_VERSION.log
TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
oc rsh -n openshift-storage $TOOLS_POD ceph -s 2>&1 | tee -a $WORKSPACE/upgrade-ocs-$UPGRADE_OCS_VERSION.log 

deactivate

popd
