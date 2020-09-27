#!/bin/bash

set -e

echo "Command invocation: $0 $1"

TOP_DIR=$(pwd)/..

if [ ! -e $TOP_DIR/files/ocp4-upi-kvm.patch ]; then
        echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
        exit 1
fi

if [ ! -e ~/pull-secret.txt ]; then
	echo "Missing ~/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
	exit 1
fi

source helper/parameters.sh

if [ "$1" == "--retry" ]; then
	cd $TOP_DIR/src/ocp4-upi-kvm
	export TF_LOG=TRACE
	export TF_LOG_PATH=/tmp/terraform.log
	/usr/local/bin/terraform apply -var-file var.tfvars -auto-approve -parallelism=3
	exit
fi

export BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}

# Internal variables, don't change unless you also modify the underlying projects

BASTION_IP=${BASTION_IP:="192.168.88.2"}

export TERRAFORM_VERSION=${TERRAFORM_VERSION:="v0.13.3"}
export GO_VERSION=${GO_VERSION:="go1.14.9"}

if [[ -z "$RHID_USERNAME" ]] || [[ -z "$RHID_PASSWORD" ]]; then
	echo "Must specify your redhat subscription RHID_USERNAME=$RHID_USERNAME and RHID_PASSWORD=$RHID_PASSWORD"
	exit 1
fi

if [[ ! -e ~/$BASTION_IMAGE ]] && [[ ! -e $IMAGES_PATH/$BASTION_IMAGE ]]; then
	echo "Missing $BASTION_IMAGE.  Get it from https://access.redhat.com/downloads/content/479/ and prepare it per README"
	exit 1
fi
if [ -e ~/$BASTION_IMAGE ]; then
	if [ ! -e "$IMAGES_PATH" ]; then
		mkdir -p $IMAGES_PATH
	fi
	mv ~/$BASTION_IMAGE $IMAGES_PATH
fi
ln -sf $IMAGES_PATH/$BASTION_IMAGE $IMAGES_PATH/bastion.qcow2

# openshift install images are publically released with every minor update.  RHCOS
# boot images are released less frequently, but follow the same version numbering scheme

INSTALLER_VERSION="latest-$OCP_VERSION"		# https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp/$INSTALLER_VERSION

case "$OCP_VERSION" in
	4.4)
		OCP_RELEASE="4.4.9"		# Latest release of OCP 4.4 at this time
		RHCOS_VERSION="4.4"
		RHCOS_RELEASE="4.4.9"
		;;
	4.5)
		OCP_RELEASE="4.5.7"		# Latest release of OCP 4.5 at this time
		RHCOS_VERSION="4.5"
		RHCOS_RELEASE="4.5.4"
		;;
	4.6)
		unset OCP_RELEASE		# Not released yet
		RHCOS_VERSION="4.5"
		RHCOS_RELEASE="4.5.4"
		INSTALLER_VERSION="latest"
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

# Get the RHCOS image associated with the specified OCP Version

if [ ! -e $IMAGES_PATH/rhcos-$RHCOS_RELEASE-ppc64le-qemu.ppc64le.qcow2 ]; then
        pushd $IMAGES_PATH
        wget https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/$RHCOS_VERSION/latest/rhcos-$RHCOS_RELEASE-ppc64le-qemu.ppc64le.qcow2.gz
        gunzip rhcos*qcow2.gz

        # Boot disk is 16G by default.  OSC workers need ~20.  These are sparse files
	# with large holes. Disk space is not allocated unless it is needed.  No penalty

        echo "Resizing VM boot image to 40G"
        qemu-img resize rhcos-$RHCOS_RELEASE-ppc64le-qemu.ppc64le.qcow2 40G
        popd
fi
ln -sf $IMAGES_PATH/rhcos-$RHCOS_RELEASE-ppc64le-qemu.ppc64le.qcow2 $IMAGES_PATH/rhcos.qcow2

# Install GO and terraform

OLD_GO_VERSION=''
if [ -e /usr/local/go/bin/go ]; then
	OLD_GO_VERSION=$(/usr/local/go/bin/go version | awk '{print $3}')
fi

INSTALLED_GO=false
if [ "$OLD_GO_VERSION" != "$GO_VERSION" ]; then
	if [ ! -e ~/$GO_VERSION.linux-ppc64le.tar.gz ]; then
		pushd ~
		wget https://golang.org/dl/$GO_VERSION.linux-ppc64le.tar.gz
		popd
	fi
	rm -rf /usr/local/go
	rm -rf /tmp/go*
	rm -rf ~/.cache/go*
	tar -C /usr/local -xzf ~/$GO_VERSION.linux-ppc64le.tar.gz
	INSTALLED_GO=true
fi
export PATH=$PATH:/usr/local/go/bin

# Install terraform and libvirt providers
OLD_TERRAFORM_VERSION=''
if [ -e /usr/local/bin/terraform ]; then
	OLD_TERRAFORM_VERSION=$(/usr/local/bin/terraform version | head -n 1| awk '{print $2}')
fi

PLUGIN_PATH=~/.local/share/terraform/plugins/registry.terraform.io

export GOPATH=~/go
if [[ "$INSTALLED_GO" == "true" ]] || [[ "$OLD_TERRAFORM_VERSION" != "$TERRAFORM_VERSION" ]] || 
   [[ ! -e $GOPATH/bin ]] || [[ ! -e $PLUGIN_PATH ]]; then

	# Clean directories for go modules

	mkdir -p $GOPATH
	rm -rf $GOPATH/*

	mkdir -p $GOPATH/bin
	export PATH=$PATH:$GOPATH/bin
	export CGO_ENABLED="1"

	# Clean directories for terraform and terraform providers

	if [ -e /usr/local/bin ]; then
		rm -f /usr/local/bin/oc			# User sometimes copies from bastion VM
		rm -f /usr/local/bin/kubectl		# User sometimes copies from bastion VM
		rm -f /usr/local/bin/terraform
	fi
	if [ -e ~/.terraform.d ]; then			# Legacy (ocp 4.4 4.5) terraform provider path
		rm -rf ~/.terraform.d/*
	fi 
	if [ -e ~/terraform ]; then			# Legacy terraform build source
		rm -rf ~/terraform
	fi

	PLATFORM=linux_ppc64le
	rm -rf $PLUGIN_PATH/*

	pushd $GOPATH

        mkdir -p $GOPATH/src/github.com/hashicorp/; cd $GOPATH/src/github.com/hashicorp

	# Build terraform

	git clone https://github.com/hashicorp/terraform.git terraform
	pushd terraform 
	git checkout -b "$TERRAFORM_VERSION" $TERRAFORM_VERSION
	TF_DEV=1 scripts/build.sh
	popd

	cp $GOPATH/bin/terraform /usr/local/bin/terraform

        mkdir -p $GOPATH/src/github.com/dmacvicar; cd $GOPATH/src/github.com/dmacvicar
        git clone https://github.com/dmacvicar/terraform-provider-libvirt.git
        pushd terraform-provider-libvirt
        make install
        popd

	mkdir -p $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$PLATFORM/
	cp $GOPATH/bin/terraform-provider-libvirt $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$PLATFORM/terraform-provider-libvirt

	VERSION=2.3.0
	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
	git clone https://github.com/terraform-providers/terraform-provider-random --branch v$VERSION
	pushd terraform-provider-random
	make build
	popd

	mkdir -p $PLUGIN_PATH/hashicorp/random/$VERSION/$PLATFORM/
	cp $GOPATH/bin/terraform-provider-random $PLUGIN_PATH/hashicorp/random/$VERSION/$PLATFORM/terraform-provider-random

	VERSION=2.1.2
	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
	git clone https://github.com/terraform-providers/terraform-provider-null --branch v$VERSION
	pushd terraform-provider-null
	make build
	popd

	mkdir -p $PLUGIN_PATH/hashicorp/null/$VERSION/$PLATFORM/
	cp $GOPATH/bin/terraform-provider-null $PLUGIN_PATH/hashicorp/null/$VERSION/$PLATFORM/terraform-provider-null

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
	cp $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$PLATFORM/terraform-provider-ignition

 	VERSION=1.2.1
	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers 
	git clone https://github.com/terraform-providers/terraform-provider-ignition --branch v$VERSION
	pushd terraform-provider-ignition
	make build
	popd

	mkdir -p $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$PLATFORM/
	cp $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$PLATFORM/terraform-provider-ignition

	popd
fi

pushd $TOP_DIR/src/ocp4-upi-kvm

# Remove files from previous cluster creation

rm -rf ~/.kube
rm -f terraform.tfstate
rm -rf .terraform

# Patch ocp4-upi-kvm submodule to enable the use of environment
# variables and manage ocp differences between releases

set -x

git checkout -- var.tfvars

case "$OCP_VERSION" in
4.4|4.5)
	git checkout -- modules/4_nodes/versions.tf
	git checkout -- modules/4_nodes/nodes.tf
	patch -p1 < $TOP_DIR/files/ocp4-upi-kvm.legacy.patch
	;;
*)
	patch -p1 < $TOP_DIR/files/ocp4-upi-kvm.patch
	;;
esac

sed -i "s|<IMAGES_PATH>|$IMAGES_PATH|g" var.tfvars
sed -i "s/<OCP_VERSION>/$OCP_VERSION/g" var.tfvars
sed -i "s/<INSTALLER_VERSION>/$INSTALLER_VERSION/g" var.tfvars
sed -i "s/<CLUSTER_DOMAIN>/$CLUSTER_DOMAIN/g" var.tfvars
sed -i "s/<BASTION_IP>/$BASTION_IP/g" var.tfvars
sed -i "s/<RHID_USERNAME>/$RHID_USERNAME/g" var.tfvars
sed -i "s/<RHID_PASSWORD>/$RHID_PASSWORD/g" var.tfvars
sed -i "s/<MASTER_DESIRED_MEM>/$MASTER_DESIRED_MEM/g" var.tfvars
sed -i "s/<MASTER_DESIRED_CPU>/$MASTER_DESIRED_CPU/g" var.tfvars
sed -i "s/<WORKER_DESIRED_MEM>/$WORKER_DESIRED_MEM/g" var.tfvars
sed -i "s/<WORKER_DESIRED_CPU>/$WORKER_DESIRED_CPU/g" var.tfvars
sed -i "s/<WORKERS>/$WORKERS/g" var.tfvars

if [ -z "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" ]; then
	sed -i 's/release_image_override/#release_image_override/' var.tfvars
else
	sed -i "s|<IMAGE_OVERRIDE>|$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE|" var.tfvars
fi

mkdir -p data

if [[ ! -e ~/.ssh/id_rsa ]] || [[ ! -e ~/.ssh/id_rsa.pub ]]; then
	if [ ! -d ~/.ssh ]; then
		mkdir ~/.ssh && chmod 700 ~/.ssh
	fi
	HOSTNAME=$(hostname -s | awk '{ print $1 }')
	ssh-keygen -t rsa -f ~/.ssh/id_rsa -N '' -C root@$HOSTNAME -q
	restorecon -Rv ~/.ssh
fi

cp ~/.ssh/id_rsa* data
cp ~/pull-secret.txt data/pull-secret.txt

export TF_LOG=TRACE
export TF_LOG_PATH=/tmp/terraform.log

/usr/local/bin/terraform init

/usr/local/bin/terraform validate

/usr/local/bin/terraform apply -var-file var.tfvars -auto-approve -parallelism=3
