#!/bin/bash

set -e

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

sudo yum -y install libffi-devel lapack atlas-devel openssl-devel gcc gcc-c++ gcc-gfortran make
sudo yum -y install python36-devel python3-setuptools python3-virtualenv python3-docutils

source helper/parameters.sh

pushd ../src/ocs-ci

rm -rf $WORKSPACE/venv

python3.6 -m venv $WORKSPACE/venv

source $WORKSPACE/venv/bin/activate		# activate named python venv

pip3 install --upgrade pip setuptools wheel
pip3 install -r requirements.txt

deactivate					# exit venv shell

popd
