# ----------------------------------------------------------------------------
# Package       : Vault
# Version       : 1.9.3
# ----------------------------------------------------------------------------

#!/bin/bash

set -e

VERSION="${VAULT_VERSION:-v1.9.3}"

yum install -y openssl sudo make git gcc wget

# Go is already installed while installing kustomize, hence exporting the path
export PATH=/usr/local/go/bin:$PATH

mkdir -p /go/src/github.com/hashicorp

export GOPATH=/go
export PATH=$PATH:$GOPATH/bin

cd /go/src/github.com/hashicorp
git clone https://github.com/hashicorp/vault
cd vault
git checkout ${VERSION}
make bootstrap && make

cp /go/bin/vault /root/

