#!/bin/bash

set -e

echo "Command invocation: $0 $1"

ARG1=$1

# openshift install images are publicly released with every minor update at
# https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp/$OCP_RELEASE
# RHCOS boot images are released less frequently, but follow the same version numbering scheme

case "$OCP_VERSION" in
	4.4)
		OCP_RELEASE="4.4.23"				# Latest release of OCP 4.4 at this time
		RHCOS_VERSION="4.4"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.4.9"			# Latest release of RHCOS 4.4 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		export INSTALL_PLAYBOOK_TAG=b07c89deacb04f996834403b1efdafb1f9a3d7c4
		;;
	4.5)
		OCP_RELEASE="4.5.11"				# Latest release of OCP 4.5 at this time
		RHCOS_VERSION="4.5"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.5.4"			# Latest release of RHCOS 4.5 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		export INSTALL_PLAYBOOK_TAG=b07c89deacb04f996834403b1efdafb1f9a3d7c4
		;;
	4.6)
		OCP_RELEASE="4.6.20"				# Latest release of OCP 4.6 at this time
		RHCOS_VERSION="4.6"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.6.8"			# Latest release of RHCOS 4.6 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		export INSTALL_PLAYBOOK_TAG=fc74d7ec06b2dd47c134c50b66b478abde32e295
		;;
	4.7)
		OCP_RELEASE="4.7.2"
		RHCOS_VERSION="4.7"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.7.0"                   # Latest release of RHCOS 4.7 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_VERSION"
		export INSTALL_PLAYBOOK_TAG=fc74d7ec06b2dd47c134c50b66b478abde32e295
		;;
	4.8)
		unset OCP_RELEASE
                RHCOS_VERSION="4.7"
                unset RHCOS_RELEASE
                RHCOS_SUFFIX="-$RHCOS_VERSION"
                export INSTALL_PLAYBOOK_TAG=fc74d7ec06b2dd47c134c50b66b478abde32e295
		;;
	*)
		echo "Invalid OCP_VERSION=$OCP_VERSION.  Supported versions are 4.4 - 4.8"
		exit 1
esac

if [ -n "$RHCOS_RELEASE" ]; then
	export OCP_INSTALLER_SUBPATH="ocp/latest-$OCP_VERSION"
elif [ -n "$OCP_RELEASE" ]; then
	export OCP_INSTALLER_SUBPATH="ocp/$OCP_RELEASE"
else
	export OCP_INSTALLER_SUBPATH="ocp-dev-preview/latest-$OCP_VERSION"
fi


# The openshift installer always installs the latest image.  The installer can be configured
# to pull older images via the environment variable OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE.
# It can also be used to specify a daily build.  For 4.6, the user should set this environment
# to a specific daily build image or leave it unset to choose the latest available image

if [ -z "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" ]; then
	REGISTRY=quay.io/openshift-release-dev/ocp-release

	# Set to the latest released image
	if [ -n "$OCP_RELEASE" ]; then
		OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$REGISTRY:$OCP_RELEASE-ppc64le"
	fi
fi
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE

if [[ -n "$RHID_USERNAME" && -n "$RHID_PASSWORD" ]]; then
	export RHID_ORG=""
	export RHID_KEY=""
else
	export RHID_USERNAME=""
	export RHID_PASSWORD=""
fi

source helper/parameters.sh

export GOROOT=$WORKSPACE/usr/local/go
export PATH=$WORKSPACE/bin:$PATH

# This is decremented after cluster creation to remove the bootstrap node

export BOOTSTRAP_CNT=1

retry=false
if [ "$ARG1" == "--retry" ]; then
	retry=true
	if [ "$PLATFORM" == kvm ]; then
		retry_version=$(sudo virsh list | grep bastion | awk '{print $2}' | sed 's/4-/4./' | sed 's/-/ /g' | awk '{print $2}' | sed 's/ocp//')
		if [ "$retry_version" != "$OCP_VERSION" ]; then
			echo "WARNING: Ignoring --retry argument.  existing version:$retry_version  requested version:$OCP_VERSION"
			retry=false
		fi
	fi
	if [ "$retry" == true ]; then
		pushd $WORKSPACE/ocs-upi-kvm/src/$OCP_PROJECT
		terraform_apply
		# Delete bootstrap to save system resources after successful cluster creation (set -e above)
		export BOOTSTRAP_CNT=0
		terraform_apply
		popd
		exit
	fi
fi

# Validate platform setup, prepare hugepages, destroy pre-existing cluster.  We are creating a new cluster

prepare_new_cluster_delete_old_cluster

# Delete old cluster commands and runtime

rm -f $WORKSPACE/bin/oc
rm -rf $WORKSPACE/auth

# Install GO and Terraform

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

	LPLATFORM=linux_ppc64le

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

	mkdir -p $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-libvirt $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$LPLATFORM/

	# The modules below are copied into the user's home directory and may be shared across cronjobs,
	# so don't update them if they are present at the desired version.  The go version that built
	# them may be different which is an exposure.  An exception is made for libvirt, because only
        # one KVM cluster is supported at a time at the system level

	VERSION=$TERRAFORM_POWERVS_VERSION
	if [ ! -e $PLUGIN_PATH/IBM-Cloud/ibm/$VERSION/$LPLATFORM/terraform-provider-ibm ]; then
		mkdir -p $GOPATH/src/github.com/IBM-Cloud; cd $GOPATH/src/github.com/IBM-Cloud
		git clone https://github.com/IBM-Cloud/terraform-provider-ibm.git  --branch v$VERSION
		pushd terraform-provider-ibm
		make build
		popd

		mkdir -p $PLUGIN_PATH/IBM-Cloud/ibm/$VERSION/$LPLATFORM/
		cp -f $GOPATH/bin/terraform-provider-ibm $PLUGIN_PATH/IBM-Cloud/ibm/$VERSION/$LPLATFORM/
	fi

	VERSION=$TERRAFORM_RANDOM_VERSION
	if [ ! -e $PLUGIN_PATH/hashicorp/random/$VERSION/$LPLATFORM/terraform-provider-random ]; then
		mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
		git clone https://github.com/terraform-providers/terraform-provider-random --branch v$VERSION
		pushd terraform-provider-random
		make build
		popd

		mkdir -p $PLUGIN_PATH/hashicorp/random/$VERSION/$LPLATFORM/
		cp -f $GOPATH/bin/terraform-provider-random $PLUGIN_PATH/hashicorp/random/$VERSION/$LPLATFORM/
	fi

	VERSION=$TERRAFORM_NULL_VERSION
	if [ ! -e $PLUGIN_PATH/hashicorp/null/$VERSION/$LPLATFORM/terraform-provider-null ]; then
		mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
		git clone https://github.com/terraform-providers/terraform-provider-null --branch v$VERSION
		pushd terraform-provider-null
		make build
		popd

		mkdir -p $PLUGIN_PATH/hashicorp/null/$VERSION/$LPLATFORM/
		cp -f $GOPATH/bin/terraform-provider-null $PLUGIN_PATH/hashicorp/null/$VERSION/$LPLATFORM/
	fi

	# OCP 4.6 upgraded to Ignition Config Spec v3.0.0 which is incompatible with the
	# format used by OCP 4.5 and 4.4, so conditionally patch ocp4-upi-xxx terraform code
	# based on the OCP version of the cluster being deployed.  files/ocp4-upi-XXX.legacy.patch
	# is used for this purpose.

	VERSION=$TERRAFORM_IGNITION_VERSION
	if [ ! -e $PLUGIN_PATH/community-terraform-providers/ignition/$VERSION/$LPLATFORM/terraform-provider-ignition ]; then
		mkdir -p $GOPATH/src/github.com/community-terraform-providers; cd $GOPATH/src/github.com/community-terraform-providers 
		git clone https://github.com/community-terraform-providers/terraform-provider-ignition --branch v$VERSION
		pushd terraform-provider-ignition
		make build
		popd

		mkdir -p $PLUGIN_PATH/community-terraform-providers/ignition/$VERSION/$LPLATFORM/
		cp -f $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/community-terraform-providers/ignition/$VERSION/$LPLATFORM/
	fi

	# This is the legacy version

	VERSION=$TERRAFORM_IGNITION_LEGACY_VERSION
	if [ ! -e $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$LPLATFORM/terraform-provider-ignition ]; then
		mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers 
		git clone https://github.com/terraform-providers/terraform-provider-ignition --branch v$VERSION
		pushd terraform-provider-ignition
		make build
		popd

		mkdir -p $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$LPLATFORM/
		cp -f $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$LPLATFORM/
	fi

	popd
fi

pushd ..

# Remove files from previous cluster creation

if [[ -d ~/.ssh ]] && [[ "$retry" == false ]]; then
	rm -f ~/.ssh/known_hosts
fi
rm -rf ~/.kube

# Reset submodule so that the patch below can be applied

git submodule deinit --force src/$OCP_PROJECT
git submodule update --init  src/$OCP_PROJECT

pushd src/$OCP_PROJECT

# Patch ocp4-upi-xxx submodule to manage differences across ocp releases.
# This mostly comes down to managing terraform modules.  A different version
# of the ignition module is required for ocp 4.6.

case "$OCP_VERSION" in
	4.4|4.5)
		if [ -e $WORKSPACE/ocs-upi-kvm/files/$PLATFORM/$OCP_PROJECT.legacy.patch ]; then
			patch -p1 < $WORKSPACE/ocs-upi-kvm/files/$PLATFORM/$OCP_PROJECT.legacy.patch
		fi
		;;
	*)
		if [ -e $WORKSPACE/ocs-upi-kvm/files/$PLATFORM/$OCP_PROJECT.patch ]; then
			patch -p1 < $WORKSPACE/ocs-upi-kvm/files/$PLATFORM/$OCP_PROJECT.patch
		fi
		;;
esac

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

terraform init

terraform validate

terraform_apply

# Delete bootstrap to save system resources after successful cluster creation (set -e above)

export BOOTSTRAP_CNT=0
terraform_apply

popd
