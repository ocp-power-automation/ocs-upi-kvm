#!/bin/bash

user=$(whoami)
if [ "$user" != root ]; then
        echo "This script must be invoked as root"
        exit 1
fi

if [ ! -e ~/pull-secret.txt ]; then
	echo "Missing ~/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
	exit 1
fi

if [ ! -e ~/auth.yaml ]; then
	echo "~/auth.yaml is required"
	exit 1
fi

source /root/venv/bin/activate                  # enter 'deactivate' in venv shell to exit

set -ex

export KUBECONFIG=~/auth/kubeconfig

TOP_DIR=$(pwd)/..

pushd $TOP_DIR/src/ocs-ci

# This patch fixes ocs catalog access.  Sets through ocs-olm-operator

git checkout -- conf/ocs_version/ocs-4.6.yaml
patch -p1 < $TOP_DIR/files/ocs-ci.patch

mkdir -p data

cp ~/auth.yaml data/auth.yaml
cp ~/pull-secret.txt data/pull-secret

run-ci -m deployment --deploy --ocsci-conf=conf/ocsci/production_powervs_upi.yaml --ocs-version 4.6 --cluster-name=ocstest --cluster-path=/root --collect-logs

popd
