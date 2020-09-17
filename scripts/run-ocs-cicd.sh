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

set -ex

TOP_DIR=$(pwd)/..

export KUBECONFIG=~/auth/kubeconfig

source /root/venv/bin/activate                  # enter 'deactivate' in venv shell to exit

pushd $TOP_DIR/src/ocs-ci

mkdir -p data

cp ~/auth.yaml data/auth.yaml
cp ~/pull-secret.txt data/pull-secret

run-ci -m deployment --deploy --ocsci-conf=conf/ocsci/production_powervs_upi.yaml --ocs-version 4.6 --cluster-name=ocstest --cluster-path=/root --collect-logs

popd
