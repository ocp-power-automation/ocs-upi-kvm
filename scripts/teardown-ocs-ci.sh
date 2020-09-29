#!/bin/bash

user=$(whoami)
if [ "$user" != root ]; then
        echo "This script must be invoked as root"
        exit 1
fi

set -ex

TOP_DIR=$(pwd)/..

export KUBECONFIG=~/auth/kubeconfig

source /root/venv/bin/activate                  # enter 'deactivate' in venv shell to exit

pushd $TOP_DIR/src/ocs-ci

run-ci -m deployment --teardown --ocsci-conf=conf/ocsci/production_powervs_upi.yaml --cluster-name=ocstest --cluster-path=/root --collect-logs

popd
