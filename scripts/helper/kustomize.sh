#!/bin/bash

set -e

ARCH=`arch`
[ "$ARCH" == "x86_64" ] && ARCH="amd64"
VERSION="${GO_VERSION:-$(curl -s 'https://go.dev/VERSION?m=text'| sed 's/go//g')}"
# Install go
wget https://golang.org/dl/go"${VERSION}".linux-"${ARCH}".tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xvzf go"${VERSION}".linux-"${ARCH}".tar.gz
export PATH=/usr/local/go/bin:$PATH

# Verify go version
go version

unset GOPATH
unset GO111MODULES

# Add github fingerprint to knownhosts
ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# clone the repo
git clone https://github.com/kubernetes-sigs/kustomize.git

# get into the repo root
cd kustomize

# build the binary
(cd kustomize; go install .)

# run it
~/go/bin/kustomize version

# copy binary in /usr/local/bin
cp ~/go/bin/kustomize /usr/local/bin/

# Verify kustomize version
kustomize version
