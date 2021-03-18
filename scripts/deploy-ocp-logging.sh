#!/bin/bash

# Deploy cluster logging.  This is dependent on ocs storage to store logs

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

if [ ! -e $WORKSPACE/env-ocp.sh ]; then
	echo "The OpenShift Cluster must be created before deploying cluster logging"
	exit 1
fi

source $WORKSPACE/env-ocp.sh

oc get namespace/openshift-storage > /dev/null 2>&1
if [ "$?" != 0 ]; then
	echo "OpenShift Container Storage must be deployed before deploying cluster logging"
	exit 1
fi

mkdir -p $WORKSPACE/deploy-ocp-logging
pushd $WORKSPACE/deploy-ocp-logging

# Copy clusterlogging configuration files to workspace as they are modified

cp -f $WORKSPACE/ocs-upi-kvm/files/cluster-logging/* .

echo "Creating namespaces for openshift-operators-redhat and openshift-logging"

oc create -f eo-namespace.yaml
oc create -f cl-namespace.yaml

echo "Creating elasticsearch operator group and subscriptions"

case "$OCP_VERSION" in
	4.4|4.5|4.6)
		CHANNEL=$OCP_VERSION
		;;
	4.7|4.8)
		CHANNEL=stable
		;;
	*)
		echo "Unsupported OCP Version $OCP_VERSION"
		exit 1
		;;
esac

oc create -f eo-og.yaml
#oc create -f eo-rbac.yaml 				# rbac is specific to ocs-ci
sed -i "s/VERSION_PLACEHOLDER/$CHANNEL/" eo-sub.yaml
oc create -f eo-sub.yaml

echo "Creating cluster-logging operator group and subscriptions"

oc create -f cl-og.yaml
sed -i "s/VERSION_PLACEHOLDER/$CHANNEL/" cl-sub.yaml
oc create -f cl-sub.yaml

sleep 1m

echo "Verifing operator installation"

oc get csv --all-namespaces | egrep 'NAMESPACE|elasticsearch|openshift-logging'

echo "Creating cluster-logging instance"

oc create -f cl-instance.yaml

popd

sleep 2m

oc get deployment -A | egrep 'NAMESPACE|logging|monitoring|operators-redhat'

es_cluster_ip=$(oc get service elasticsearch -n openshift-logging | grep ^elasticsearch | awk '{print $3}')
if [ -n "$es_cluster_ip" ]; then
	pushd ../src/ocs-ci
	echo "Patching defaults.py for external (to ocs-ci) Elasticsearch Cluster IP $es_cluster_ip"
	sed -i "s/ES_SERVER_PLACEHOLDER/$es_cluster_ip/" ocs_ci/ocs/defaults.py
	files=$(find ocs_ci/templates/workloads -type f | xargs grep ES_SERVER_PLACEHOLDER | awk '{print $1}' | sed 's/://')
	if [ -n "$files" ]; then
		for i in "$files"
		do
			echo "Patching workload template $i with Elasticsearch Cluster IP $es_cluster_ip"
			find $i | xargs sed -i "s/ES_SERVER_PLACEHOLDER/$es_cluster_ip/"
		done
	fi
	popd
else
	echo "WARNING: Cluster logging is not configured which is required for ocs-ci performance testing"
fi

