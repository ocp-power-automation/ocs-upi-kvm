#!/bin/bash

set -e

echo "Command invocation: $0 $1"

ARG1=$1

# openshift install images are publicly released with every minor update at
# https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp/$OCP_RELEASE
# RHCOS boot images are released less frequently, but follow the same version numbering scheme

case "$OCP_VERSION" in
	4.4)
		OCP_RELEASE="4.4.33"				# Latest release of OCP 4.4 at this time
		RHCOS_VERSION="4.4"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.4.9"			# Latest release of RHCOS 4.4 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		;;
	4.5)
		OCP_RELEASE="4.5.41"				# Latest release of OCP 4.5 at this time
		RHCOS_VERSION="4.5"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.5.4"			# Latest release of RHCOS 4.5 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		;;
	4.6)
		OCP_RELEASE="4.6.56"				# Latest release of OCP 4.6 at this time
		RHCOS_VERSION="4.6"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.6.47"			# Latest release of RHCOS 4.6 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		;;
	4.7)
		OCP_RELEASE="4.7.52"
		RHCOS_VERSION="4.7"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.7.33"                   # Latest release of RHCOS 4.7 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		;;
	4.8)
		OCP_RELEASE="4.8.42"
		RHCOS_VERSION="4.8"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.8.14"                   # Latest release of RHCOS 4.8 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		;;
	4.9)
		OCP_RELEASE="4.9.37"
		RHCOS_VERSION="4.9"
		if [ -z "$RHCOS_RELEASE" ]; then
			RHCOS_RELEASE="4.9.0"                   # Latest release of RHCOS 4.9 at this time
		fi
		RHCOS_SUFFIX="-$RHCOS_RELEASE"
		;;
	4.10)
		OCP_RELEASE="4.10.18"
		RHCOS_VERSION="4.10"
                if [ -z "$RHCOS_RELEASE" ]; then
                        RHCOS_RELEASE="4.10.3"                   # Latest release of RHCOS 4.10 at this time
                fi
                RHCOS_SUFFIX="-$RHCOS_RELEASE"
		;;
	4.11)
		unset OCP_RELEASE
		RHCOS_VERSION="4.10"
		unset RHCOS_RELEASE
		RHCOS_SUFFIX="-$RHCOS_VERSION"
		;;
	*)
		echo "Invalid OCP_VERSION=$OCP_VERSION.  Supported versions are 4.4 - 4.11"
		exit 1
esac

if [ -n "$RHCOS_RELEASE" ]; then
	export OCP_INSTALLER_SUBPATH="ocp/stable-$OCP_VERSION"
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

set +e

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
		rc=$?
		if [ "$rc" == 0 ]; then
			# Delete bootstrap to save system resources after successful cluster creation
			export BOOTSTRAP_CNT=0
			terraform_apply
		fi
		popd
		exit $rc
	fi
fi

set -e

# Validate platform setup, prepare hugepages, destroy pre-existing cluster.  We are creating a new cluster

prepare_new_cluster_delete_old_cluster

# Delete old cluster commands and runtime

rm -f $WORKSPACE/bin/oc
rm -rf $WORKSPACE/auth

# Install GO and Terraform

PROVIDER_DIR=$WORKSPACE/.providers
PLUGIN_PATH=$PROVIDER_DIR/registry.terraform.io
LPLATFORM=linux_ppc64le

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

	# If GO Version has changed, rebuild the current set of terraform modules

	rm -rf $PLUGIN_PATH/dmacvicar/libvirt/1.0.0
	rm -rf $PLUGIN_PATH/IBM-Cloud/ibm/$TERRAFORM_POWERVS_VERSION
	rm -rf $PLUGIN_PATH/terraform-provider-openstack/openstack/$TERRAFORM_OPENSTACK_VERSION
	rm -rf $PLUGIN_PATH/hashicorp/random/$TERRAFORM_RANDOM_VERSION
	rm -rf $PLUGIN_PATH/hashicorp/null/$TERRAFORM_NULL_VERSION
	rm -rf $PLUGIN_PATH/community-terraform-providers/ignition/$TERRAFORM_IGNITION_VERSION
	rm -rf $PLUGIN_PATH/terraform-providers/ignition/$TERRAFORM_IGNITION_LEGACY_VERSION
fi

# Install terraform and libvirt providers

OLD_TERRAFORM_VERSION=''
if [ -e $WORKSPACE/bin/terraform ]; then
	OLD_TERRAFORM_VERSION=$($WORKSPACE/bin/terraform version | head -n 1| awk '{print $2}')
fi

export GOPATH=$WORKSPACE/go
if [[ "$INSTALLED_GO" == "true" ]] || [[ "$OLD_TERRAFORM_VERSION" != "$TERRAFORM_VERSION" ]] || 
	[[ ! -e $GOPATH/bin ]] || [[ ! -e $PLUGIN_PATH ]]; then

	# Clean directories for go modules

	mkdir -p $GOPATH
	sudo -sE rm -rf $GOPATH/*

	mkdir -p $GOPATH/bin
	export PATH=$GOPATH/bin:$PATH
	export CGO_ENABLED="1"

	pushd $GOPATH

	mkdir -p $GOPATH/src/github.com/hashicorp/; cd $GOPATH/src/github.com/hashicorp

	# Build terraform

	git clone https://github.com/hashicorp/terraform.git terraform
	pushd terraform 
	git checkout -b "$TERRAFORM_VERSION" $TERRAFORM_VERSION
	TF_DEV=1 scripts/build.sh
	popd

	cp -f $GOPATH/bin/terraform $WORKSPACE/bin/terraform

	popd
fi

# The modules below are copied into the user's home directory and may be shared across cronjobs,
# so don't update them if they are present at the desired version.  The go version that built
# them may be different which is an exposure.  An exception is made for libvirt, because only
# one KVM cluster is supported at a time at the system level

if [ ! -e $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$LPLATFORM/terraform-provider-libvirt ]; then
	pushd $GOPATH/src/github.com

	mkdir -p $GOPATH/src/github.com/dmacvicar/; cd $GOPATH/src/github.com/dmacvicar
	rm -rf terraform-provider-libvirt
	git clone https://github.com/dmacvicar/terraform-provider-libvirt.git --branch v0.6.3
	pushd terraform-provider-libvirt
	make install
	popd

	mkdir -p $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-libvirt $PLUGIN_PATH/dmacvicar/libvirt/1.0.0/$LPLATFORM/
	popd
fi

VERSION=$TERRAFORM_POWERVS_VERSION
if [ ! -e $PLUGIN_PATH/IBM-Cloud/ibm/$VERSION/$LPLATFORM/terraform-provider-ibm ]; then
	pushd $GOPATH/src/github.com

	mkdir -p $GOPATH/src/github.com/IBM-Cloud; cd $GOPATH/src/github.com/IBM-Cloud
	rm -rf terraform-provider-ibm
	git clone https://github.com/IBM-Cloud/terraform-provider-ibm.git  --branch v$VERSION
	pushd terraform-provider-ibm
	make build
	popd

	mkdir -p $PLUGIN_PATH/IBM-Cloud/ibm/$VERSION/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-ibm $PLUGIN_PATH/IBM-Cloud/ibm/$VERSION/$LPLATFORM/
	popd
fi

VERSION=$TERRAFORM_OPENSTACK_VERSION
if [ ! -e $PLUGIN_PATH/terraform-provider-openstack/openstack/$VERSION/$LPLATFORM/terraform-provider-openstack ]; then
	pushd $GOPATH/src/github.com

	mkdir -p $GOPATH/src/github.com/terraform-provider-openstack; cd $GOPATH/src/github.com/terraform-provider-openstack
	rm -rf terraform-provider-openstack
	git clone https://github.com/terraform-provider-openstack/terraform-provider-openstack --branch v$VERSION
	pushd terraform-provider-openstack
	make build
	popd

	mkdir -p $PLUGIN_PATH/terraform-provider-openstack/openstack/$VERSION/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-openstack $PLUGIN_PATH/terraform-provider-openstack/openstack/$VERSION/$LPLATFORM/
	popd
fi

VERSION=$TERRAFORM_RANDOM_VERSION
if [ ! -e $PLUGIN_PATH/hashicorp/random/$VERSION/$LPLATFORM/terraform-provider-random ]; then
	pushd $GOPATH/src/github.com

	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
	rm -rf terraform-provider-random
	git clone https://github.com/terraform-providers/terraform-provider-random --branch v$VERSION
	pushd terraform-provider-random
	make build
	popd

	mkdir -p $PLUGIN_PATH/hashicorp/random/$VERSION/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-random $PLUGIN_PATH/hashicorp/random/$VERSION/$LPLATFORM/
	popd
fi

VERSION=$TERRAFORM_NULL_VERSION
if [ ! -e $PLUGIN_PATH/hashicorp/null/$VERSION/$LPLATFORM/terraform-provider-null ]; then
	pushd $GOPATH/src/github.com

	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers
	rm -rf terraform-provider-null
	git clone https://github.com/terraform-providers/terraform-provider-null --branch v$VERSION
	pushd terraform-provider-null
	make build
	popd

	mkdir -p $PLUGIN_PATH/hashicorp/null/$VERSION/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-null $PLUGIN_PATH/hashicorp/null/$VERSION/$LPLATFORM/
	popd
fi

# OCP 4.6 upgraded to Ignition Config Spec v3.0.0 which is incompatible with the previous format
# used with OCP 4.5 and 4.4, so provide both the new and legacy versions of the ignition module

VERSION=$TERRAFORM_IGNITION_VERSION
if [ ! -e $PLUGIN_PATH/community-terraform-providers/ignition/$VERSION/$LPLATFORM/terraform-provider-ignition ]; then
	pushd $GOPATH/src/github.com

	mkdir -p $GOPATH/src/github.com/community-terraform-providers; cd $GOPATH/src/github.com/community-terraform-providers 
	rm -rf terraform-provider-ignition
	git clone https://github.com/community-terraform-providers/terraform-provider-ignition --branch v$VERSION
	pushd terraform-provider-ignition
	make build
	popd

	mkdir -p $PLUGIN_PATH/community-terraform-providers/ignition/$VERSION/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/community-terraform-providers/ignition/$VERSION/$LPLATFORM/
	popd
fi

# This is the legacy version for ocp pre-4.6

VERSION=$TERRAFORM_IGNITION_LEGACY_VERSION
if [ ! -e $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$LPLATFORM/terraform-provider-ignition ]; then
	pushd $GOPATH/src/github.com

	mkdir -p $GOPATH/src/github.com/terraform-providers; cd $GOPATH/src/github.com/terraform-providers 
	rm -rf terraform-provider-ignition
	git clone https://github.com/terraform-providers/terraform-provider-ignition --branch v$VERSION
	pushd terraform-provider-ignition
	make build
	popd

	mkdir -p $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$LPLATFORM/
	cp -f $GOPATH/bin/terraform-provider-ignition $PLUGIN_PATH/terraform-providers/ignition/$VERSION/$LPLATFORM/
	popd
fi

pushd ..

# Remove files from previous cluster creation

if [[ "$PLATFORM" != powervs ]] && [[ -d ~/.ssh ]] && [[ "$retry" == false ]]; then
	# KVM uses the same ip addresses every time, so known hosts contains old keys that conflict
	# powervm aggregates small sets of ip addresses which results in frequent reuse of a small set
	rm -f ~/.ssh/known_hosts
fi
rm -rf ~/.kube

# Reset submodule so that patches can be applied.  There are no code modifications

git submodule deinit --force src/$OCP_PROJECT
git submodule update --init  src/$OCP_PROJECT

pushd src/$OCP_PROJECT

set +e

case "$OCP_VERSION" in
4.4|4.5|4.6|4.7|4.8|4.9|4.10)
	if [ -z "$OCP_PROJECT_COMMIT" ]; then
		echo "Internal error: OCP_PROJECT_COMMIT is not set"
		exit 1
	fi
	git checkout $OCP_PROJECT_COMMIT
	;;
*)
	# submodule is committed to ocs-upi-kvm at the desired commit on master branch
	;;
esac

set -e

if [ -e $WORKSPACE/ocs-upi-kvm/files/$OCP_PROJECT/$OCP_VERSION/$OCP_PROJECT.patch ]; then
	patch -p1 < $WORKSPACE/ocs-upi-kvm/files/$OCP_PROJECT/$OCP_VERSION/$OCP_PROJECT.patch
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

set +e

terraform init --plugin-dir $PROVIDER_DIR
terraform validate
terraform_apply
rc=$?
if [ "$rc" == 0 ]; then
	# Delete bootstrap to save system resources after successful cluster creation
	export BOOTSTRAP_CNT=0
	terraform_apply
	if [ "$?" != 0 ]; then
		echo "Terraform_apply failed deleting bootstrap node"
	fi
fi

popd

exit $rc
