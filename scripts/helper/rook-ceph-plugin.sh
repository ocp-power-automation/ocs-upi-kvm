#!/bin/bash

set -e


if [ -e /usr/local/go/bin/go ]; then
      echo "Go binary is already installed, hence exporting the path."
      export PATH=/usr/local/go/bin:$PATH
else
      echo "Go binary not found. Installing Go..."
      ARCH=`arch`
      [ "$ARCH" == "x86_64" ] && ARCH="amd64"
      VERSION="${GO_VERSION:-$(curl -s https://go.dev/dl/?mode=json | jq -r '.[0].version')}"
      wget https://golang.org/dl/"${VERSION}".linux-"${ARCH}".tar.gz
      rm -rf /usr/local/go && tar -C /usr/local -xvzf "${VERSION}".linux-"${ARCH}".tar.gz
      export PATH=/usr/local/go/bin:$PATH
fi

echo -e "\n Cloning kubectl-rook-ceph repository...\n"

git clone https://github.com/rook/kubectl-rook-ceph.git
cd kubectl-rook-ceph/ && make build
./bin/kubectl-rook-ceph --help

echo -e "\n Kubectl Rook Ceph Plugin installed Successfully"

oc get namespace/openshift-storage > /dev/null 2>&1
if [ "$?" == 0 ]; then
	./bin/kubectl-rook-ceph -n openshift-storage rook version
fi
