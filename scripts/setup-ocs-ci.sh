#!/bin/bash

set -e

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

sudo yum -y install libffi-devel lapack atlas-devel gcc-gfortran openssl-devel gcc-gfortran
sudo yum -y install python38-devel python38-setuptools python38-Cython python3-virtualenv python3-docutils

source helper/parameters.sh

pushd ../src/ocs-ci

rm -rf $WORKSPACE/venv

python3.8 -m venv $WORKSPACE/venv

source $WORKSPACE/venv/bin/activate		# activate named python venv

pip install --upgrade pip setuptools
pip install wheel
pip install -r requirements.txt

deactivate					# exit venv shell

popd
