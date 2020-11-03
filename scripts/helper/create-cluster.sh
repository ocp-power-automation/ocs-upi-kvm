#!/bin/bash

echo "Command invocation: $0 $1"

if [[ -z "$RHID_USERNAME" && -z "$RHID_PASSWORD" && -z "$RHID_ORG" && -z "$RHID_KEY" ]]; then
	echo "ERROR: Environment variables RHID_USERNAME and RHID_PASSWORD must both be set"
	echo "ERROR: OR"
	echo "ERROR: Environment variables RHID_ORG and RHID_KEY must both be set"
	exit 1
fi

if [[ -z "$RHID_USERNAME" && -n "$RHID_PASSWORD" ]] || [[ -n "$RHID_USERNAME" && -z "$RHID_PASSWORD" ]]; then
	echo "ERROR: Environment variables RHID_USERNAME and RHID_PASSWORD must both be set"
	exit 1
elif [[ -z "$RHID_ORG" && -n "$RHID_KEY" ]] || [[ -n "$RHID_ORG" && -z "$RHID_KEY" ]]; then
	echo "ERROR: Environment variables RHID_ORG and RHID_KEY must both be set"
	exit 1
fi

if [ ! -e helper/parameters.sh ]; then
	echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh
export SANITIZED_OCP_VERSION

function terraform_apply () {
	cat $WORKSPACE/ocs-upi-kvm/files/site.tfvars.in | envsubst > $WORKSPACE/site.tfvars
	echo "site.tfvars:"
	cat $WORKSPACE/site.tfvars 
	terraform apply -var-file var.tfvars -var-file $WORKSPACE/site.tfvars -auto-approve -parallelism=3
}

if [ "$1" == "--retry" ]; then
	cd $WORKSPACE/ocs-upi-kvm/src/ocp4-upi-kvm
	export TF_LOG=TRACE
	export TF_LOG_PATH=$WORKSPACE/terraform.log
	terraform_apply
	exit
fi

if [ ! -e $WORKSPACE/pull-secret.txt ]; then
	echo "Missing $WORKSPACE/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
	exit 1
fi

export GOROOT=$WORKSPACE/usr/local/go
export PATH=$WORKSPACE/bin:$PATH

set -e

# Internal variables -- don't change unless you also modify the underlying projects
export TERRAFORM_VERSION=${TERRAFORM_VERSION:="v0.13.3"}
export GO_VERSION=${GO_VERSION:="go1.14.9"}

file_present $IMAGES_PATH/$BASTION_IMAGE
if [[ ! -e $WORKSPACE/$BASTION_IMAGE ]] && [[ "$file_rc" != 0 ]]; then
	echo "ERROR: Missing $BASTION_IMAGE.  Get it from https://access.redhat.com/downloads/content/479/ and prepare it per README"
	exit 1
fi
if [[ -e $WORKSPACE/$BASTION_IMAGE ]] && [[ "$file_rc" != 0 ]]; then
	sudo -sE mkdir -p $IMAGES_PATH 
	sudo -sE mv -f $WORKSPACE/$BASTION_IMAGE $IMAGES_PATH
fi

# openshift install images are publicly released with every minor update at
# https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp/$OCP_RELEASE
# RHCOS boot images are released less frequently, but follow the same version numbering scheme

case "$OCP_VERSION" in
	4.4)
		OCP_RELEASE="4.4.23"		# Latest release of OCP 4.4 at this time
		RHCOS_VERSION="4.4"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.4.9"	# Latest release of RHCOS 4.4 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		export INSTALL_PLAYBOOK_TAG=b07c89deacb04f996834403b1efdafb1f9a3d7c4
		;;
	4.5)
		OCP_RELEASE="4.5.11"		# Latest release of OCP 4.5 at this time
		RHCOS_VERSION="4.5"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.5.4"	# Latest release of RHCOS 4.5 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		export INSTALL_PLAYBOOK_TAG=b07c89deacb04f996834403b1efdafb1f9a3d7c4
		;;
	4.6)
		OCP_RELEASE="4.6.1"		# Latest release of OCP 4.6 at this time
		RHCOS_VERSION="4.6"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.6.1"	# Latest release of RHCOS 4.6 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		export INSTALL_PLAYBOOK_TAG=c6e6038dba0856e621697c876bd3a65927f46166
		;;
	*)
		echo "Invalid OCP_VERSION=$OCP_VERSION.  Supported versions are 4.4, 4.5, and 4.6"
		exit 1
esac

# The openshift installer always installs the latest image.  The installer can be configured
# to pull older images via the environment variable OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE.
# It can also be used to specify a daily build.  For 4.6, the user should set this environment
# to a specific daily build image or leave it unset to choose the latest available image

if [ -z "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" ]; then
	REGISTRY=registry.svc.ci.openshift.org/ocp-ppc64le/release-ppc64le

	# Set to the latest released image
	if [ -n "$OCP_RELEASE" ]; then
		OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$REGISTRY:$OCP_RELEASE"
	fi
fi
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE

# Get the RHCOS image associated with the specified OCP Version and copy it to
# IMAGES_PATH and normalize the name of the image with a soft link with RHCOS_SUFFIX
# so that it referenced with a common naming scheme.  This image is the boot disk of
# each VM and needs to be resized to accomodate OCS.  There is no penalty for specifying
# a larger size than what is actually needed as the qcow2 image is a sparse file.

file_present $IMAGES_PATH/rhcos${RHCOS_SUFFIX}.qcow2
if [ "$file_rc" != 0 ]; then
	pushd $WORKSPACE
	rm -f rhcos*qcow2.gz
	if [ -n "$RHCOS_RELEASE" ]; then
		wget -nv https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/$RHCOS_VERSION/$RHCOS_RELEASE/rhcos-$RHCOS_RELEASE-ppc64le-qemu.ppc64le.qcow2.gz
	else
		wget -nv https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/pre-release/latest-$RHCOS_VERSION/rhcos-qemu.ppc64le.qcow2.gz
	fi
	file=$(ls -1 rhcos*qcow2.gz | tail -n 1)
	echo "Unzipping $file"
	gunzip -f $file
	file=${file/.gz/}

	echo "Resizing $file (VM boot image) to 40G"
	qemu-img resize $file 40G
	sudo -sE mv -f $file $IMAGES_PATH

	sudo -sE ln -sf $IMAGES_PATH/$file $IMAGES_PATH/rhcos${RHCOS_SUFFIX}.qcow2
	popd
fi

echo "Normalized RHCOS image name is rhcos${RHCOS_SUFFIX}.qcow2"
export RHCOS_IMAGE=rhcos${RHCOS_SUFFIX}.qcow2

# Install GO and terraform

OLD_GO_VERSION=''
if [ -e $WORKSPACE/bin/go ]; then
	OLD_GO_VERSION=$($WORKSPACE/bin/go version | awk '{print $3}')
fi

INSTALLED_GO=false
if [ "$OLD_GO_VERSION" != "$GO_VERSION" ]; then
	pushd $WORKSPACE
	rm -f $GO_VERSION.linux-ppc64le.tar.gz
	wget -nv https://golang.org/dl/$GO_VERSION.linux-ppc64le.tar.gz
	popd

	rm -rf $WORKSPACE/usr/local/go
	mkdir -p $WORKSPACE/usr/local
	tar -C $WORKSPACE/usr/local -xzf $WORKSPACE/$GO_VERSION.linux-ppc64le.tar.gz

	# Clean $WORKSPACE/bin as it will be entirely rebuilt

	mkdir -p $WORKSPACE/bin
	rm -rf $WORKSPACE/bin/*
	cp $WORKSPACE/usr/local/go/bin/* $WORKSPACE/bin
	INSTALLED_GO=true
fi

# Install terraform and libvirt providers

OLD_TERRAFORM_VERSION=''
if [ -e $WORKSPACE/bin/terraform ]; then
	OLD_TERRAFORM_VERSION=$($WORKSPACE/bin/terraform version | head -n 1| awk '{print $2}')
fi

# Terraform modules built below are versioned so they can be shared

PLUGIN_PATH=~/.terraform.d/plugins/registry.terraform.io

export GOPATH=$WORKSPACE/go
if [[ "$INSTALLED_GO" == "true" ]] || [[ "$OLD_TERRAFORM_VERSION" != "$TERRAFORM_VERSION" ]] || 
	[[ ! -e $GOPATH/bin ]] || [[ ! -e $PLUGIN_PATH ]]; then

	# Clean directories for go modules

	mkdir -p $GOPATH
	sudo -sE rm -rf $GOPATH/*

	mkdir -p $GOPATH/bin
	export PATH=$GOPATH/bin:$PATH
	export CGO_ENABLED="1"

	PLATFORM=linux_ppc64le

	pushd $GOPATH

	mkdir -p $GOPATH/src/github.com/hashicorp/; cd $GOPATH/src/github.com/hashicorp

	# Build terraform

	git clone https://github.com/hashicorp/terraform.git terraform
	pushd terraform 
	git checkout -b "$TERRAFORM_VERSION" $TERRAFORM_VERSION
	TF_DEV=1 scripts/build.sh
	popd

	cp -f $GOPATH/bin/terraform $WORKSPACE/bin/terraform

	mkdir -p $GOPATH/src/github.com/dmacvicar; cd $GOPATH/src/github.com/dmacvicar
	git clone https://github.com/dmacvicar/terraform-provider-libvirt.git
	pushd terraform-provider-libvirt
	make install
	popd

	mkdir -p $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$PLATFORM/
	cp -f $GOPATH/bin/terraform-provider-libvirt $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$PLATFORM/

	VERSION=2.3.0
	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
	git clone https://github.com/terraform-providers/terraform-provider-random --branch v$VERSION
	pushd terraform-provider-random
	make build
	popd

	mkdir -p $PLUGIN_PATH/hashicorp/random/$VERSION/$PLATFORM/
	cp -f $GOPATH/bin/terraform-provider-random $PLUGIN_PATH/hashicorp/random/$VERSION/$PLATFORM/

	VERSION=2.1.2
	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
	git clone https://github.com/terraform-providers/terraform-provider-null --branch v$VERSION
	pushd terraform-provider-null
	make build
	popd

	mkdir -p $PLUGIN_PATH/hashicorp/null/$VERSION/$PLATFORM/
	cp -f $GOPATH/bin/terraform-provider-null $PLUGIN_PATH/hashicorp/null/$VERSION/$PLATFORM/

	# OCP 4.6 upgraded to Ignition Config Spec v3.0.0 which is incompatible with the
	# format used by OCP 4.5 and 4.4, so use terraform versioning to specify which one
	# should be loaded.  This is accomplished by conditionally patching a very small
	# amount of terraform data and code based on the OCP version being deployed
	# enabling bug fixes and enhancements to be more easily integrated.

	VERSION=2.1.0
	mkdir -p $GOPATH/src/github.com/community-terraform-providers; cd $GOPATH/src/github.com/community-terraform-providers 
	git clone https://github.com/community-terraform-providers/terraform-provider-ignition --branch v$VERSION
	pushd terraform-provider-ignition
	make build
	popd

	mkdir -p $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$PLATFORM/
	cp -f $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$PLATFORM/

	VERSION=1.2.1
	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers 
	git clone https://github.com/terraform-providers/terraform-provider-ignition --branch v$VERSION
	pushd terraform-provider-ignition
	make build
	popd

	mkdir -p $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$PLATFORM/
	cp -f $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$PLATFORM/

	popd
fi

pushd ..
set -x

# Remove files from previous cluster creation

rm -rf ~/.kube

# Reset submodule so that the patch below can be applied

git submodule deinit --force src/ocp4-upi-kvm
git submodule update --init  src/ocp4-upi-kvm

pushd src/ocp4-upi-kvm

# Patch ocp4-upi-kvm submodule to manage differences across ocp releases.
# This mostly comes down to managing terraform modules.  A different version
# of the ignition module is required for ocp 4.6.

case "$OCP_VERSION" in
4.4|4.5)
	if [ -e $WORKSPACE/ocs-upi-kvm/files/ocp4-upi-kvm.legacy.patch ]; then
		patch -p1 < $WORKSPACE/ocs-upi-kvm/files/ocp4-upi-kvm.legacy.patch
	fi
	;;
*)
	if [ -e $WORKSPACE/ocs-upi-kvm/files/ocp4-upi-kvm.patch ]; then
		patch -p1 < $WORKSPACE/ocs-upi-kvm/files/ocp4-upi-kvm.patch
	fi
	;;
esac

if [ -n "$RHCOS_RELEASE" ]; then
	export OCP_INSTALLER_SUBPATH="ocp/latest-$OCP_VERSION"
elif [ -n "$OCP_RELEASE" ]; then
	export OCP_INSTALLER_SUBPATH="ocp/$OCP_RELEASE"
else
	export OCP_INSTALLER_SUBPATH="ocp-dev-preview/latest-$OCP_VERSION"
fi

if [[ -n "$RHID_USERNAME" && -n "$RHID_PASSWORD" ]]; then
	export RHID_ORG=""
	export RHID_KEY=""
else
	export RHID_USERNAME=""
	export RHID_PASSWORD=""
fi

mkdir -p data

if [[ ! -e ~/.ssh/id_rsa ]] || [[ ! -e ~/.ssh/id_rsa.pub ]]; then
	if [ ! -d ~/.ssh ]; then
		mkdir ~/.ssh && chmod 700 ~/.ssh
	fi
	HOSTNAME=$(hostname -s | awk '{ print $1 }')
	USER=$(whoami)
	ssh-keygen -t rsa -f ~/.ssh/id_rsa -N '' -C $USER@$HOSTNAME -q
	chmod 600 ~/.ssh/id_rsa*
	/usr/sbin/restorecon -Rv ~/.ssh
fi

cp ~/.ssh/id_rsa* data
cp $WORKSPACE/pull-secret.txt data/pull-secret.txt

export TF_LOG=TRACE
export TF_LOG_PATH=$WORKSPACE/terraform.log

terraform init

terraform validate

terraform_apply
