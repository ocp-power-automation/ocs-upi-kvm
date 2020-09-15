#!/bin/bash

user=$(whoami)
if [ "$user" != root ]; then
        echo "This script must be invoked as root"
        exit 1
fi

set -ex

TOP_DIR=$(pwd)/..

yum -y install libffi-devel lapack atlas-devel gcc-gfortran openssl-devel gcc-gfortran
yum -y install python38-devel python38-setuptools python38-Cython python3-virtualenv python3-docutils

python3.8 -m venv /root/venv
source /root/venv/bin/activate			# activate named python venv

pip install --upgrade pip setuptools
pip install wheel

pushd $TOP_DIR/src/ocs-ci
pip install -r requirements.txt
popd

deactivate					# exit venv shell
