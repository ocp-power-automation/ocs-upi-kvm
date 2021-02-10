#!/bin/bash

# Deploy cluster logging.  This is dependent on ocs storage to store logs

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

mkdir -p $WORKSPACE/deploy-ocp-logging
pushd $WORKSPACE/deploy-ocp-logging

# Copy clusterlogging configuration files to workspace as they are modified

cp -f $WORKSPACE/ocs-upi-kvm/files/logging/* .

echo "Creating namespaces for openshift-operators-redhat and openshift-logging"

oc create -f eo-namespace.yaml
oc create -f cl-namespace.yaml

echo "Creating elasticsearch operator group and subscriptions"

oc create -f eo-og.yaml
oc create -f eo-rbac.yaml 					# rbac is specific to ocs-ci
sed -i "s/VERSION_PLACEHOLDER/$OCP_VERSION/" eo-sub.yaml
oc create -f eo-sub.yaml

echo "Creating cluster-logging operator group and subscriptions"

oc create -f cl-og.yaml
sed -i "s/VERSION_PLACEHOLDER/$OCP_VERSION/" cl-sub.yaml
oc create -f cl-sub.yaml

sleep 1m

echo "Verifing operator installation"

oc get csv --all-namespaces | egrep 'NAMESPACE|elasticsearch|openshift-logging'

echo "Creating cluster-logging instance"

oc create -f instance.yaml

sleep 2m

oc get deployment -A | egrep 'NAMESPACE|logging|monitoring|operators-redhat'
