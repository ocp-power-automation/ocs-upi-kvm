#!/bin/bash

ulimit -s unlimited

# Either username / password or org / key.  Username / password takes precedence

export RHID_USERNAME=${RHID_USERNAME:=""}
export RHID_PASSWORD=${RHID_PASSWORD:=""}

export RHID_ORG=${RHID_ORG:=""}
export RHID_KEY=${RHID_KEY:=""}

export PLATFORM=${PLATFORM:="kvm"}

export OCP_VERSION=${OCP_VERSION:="4.6"}

export OCS_VERSION=${OCS_VERSION:="4.6"}
export OCS_REGISTRY_IMAGE=${OCS_REGISTRY_IMAGE:="quay.io/rhceph-dev/ocs-registry:latest-$OCS_VERSION"}

export WORKERS=${WORKERS:=3}

# Two DNS servers are configured by default.  If the cluster is behind a firewall, the second DNS server
# may be overridden to specify a DNS server behind the firewall by setting DNS_BACKUP_SERVER

export DNS_BACKUP_SERVER=${DNS_BACKUP_SERVER:="1.1.1.1"}

# If chrony is enabled, then the list of ntp servers must be specified

export CHRONY_CONFIG=${CHRONY_CONFIG:="true"}
CHRONY_SERVER1="{\"server\": \"0.rhel.pool.ntp.org\",\"options\": \"iburst\"}"
CHRONY_SERVER2="{\"server\": \"1.rhel.pool.ntp.org\",\"options\": \"iburst\"}"
export CHRONY_CONFIG_SERVERS=${CHRONY_CONFIG_SERVERS:="$CHRONY_SERVER1, $CHRONY_SERVER2"}

source helper/$PLATFORM/parameters.sh

############################## Internal variables & functions ###############################

# Sanitize the user specified ocp version which is included in the cluster name.  The cluster
# name should not include dots (.) as this is reflected in the fully qualified hostname which
# confuses DHCP.  For example, bastion-test-ocp4.6.tt.testing

export SANITIZED_OCP_VERSION=${OCP_VERSION/./-}

GO_VERSION=${GO_VERSION:="go1.15.10"}
TERRAFORM_VERSION=${TERRAFORM_VERSION:="v0.13.6"}
TERRAFORM_RANDOM_VERSION=${TERRAFORM_RANDOM_VERSION:="2.3.1"}
TERRAFORM_NULL_VERSION=${TERRAFORM_NULL_VERSION:="2.1.2"}
TERRAFORM_IGNITION_VERSION=${TERRAFORM_IGNITION_VERSION:="2.1.1"}
TERRAFORM_IGNITION_LEGACY_VERSION=${TERRAFORM_IGNITION_LEGACY_VERSION:="1.2.1"}
TERRAFORM_POWERVS_VERSION=${TERRAFORM_POWERVS_VERSION:="1.21.0"}

# WORKSPACE is a jenkins environment variable denoting a dedicated execution environment
# that does not overlap with other jobs.  For this project, there are required input and
# output files that should be placed outside the git project itself.  If a workspace
# is not defined, then assume it is the parent directory of the project.

if [ -z "$WORKSPACE" ]; then
	cdir="$(pwd)"
	if [[ "$cdir" =~ "ocs-upi-kvm" ]]; then
		cdirnames=$(echo $cdir | sed 's/\// /g')
		dir=""
		for i in $cdirnames
		do
			if [ "$i" == "ocs-upi-kvm" ]; then
				break
			fi
			dir="$dir/$i"
		done
		WORKSPACE="$dir"
	elif [ -e ocs-upi-kvm ]; then
		WORKSPACE="$cdir"
	else
		WORKSPACE="$HOME"
	fi
fi

# Files in IMAGES_PATH are not visible to non-root users.  This provides a lookup function

file_rc=
function file_present ( ) {
	file=$1

	set +e
	ls_out=$(sudo ls $1)
	set -e

	if [ -n "$ls_out" ]; then
		file_rc=0
	else
		file_rc=1
	fi
}

function update_supplemental_ocsci_config () {

	# Current directory is assumed to be ocs-upi-kvm/src/ocs-ci

	yq -y -i '.RUN.log_dir |= env.LOGDIR' $WORKSPACE/ocs-ci-conf.yaml
	yq -y -i '.DEPLOYMENT.ocs_registry_image |= env.OCS_REGISTRY_IMAGE' $WORKSPACE/ocs-ci-conf.yaml
	yq -y -i '.DEPLOYMENT.skip_download_client |= true' $WORKSPACE/ocs-ci-conf.yaml

	export ocp_must_gather=quay.io/rhceph-dev/ocs-must-gather:latest-$OCS_VERSION
	yq -y -i '.REPORTING.ocp_must_gather_image |= env.ocp_must_gather' $WORKSPACE/ocs-ci-conf.yaml

	if [ -e ../../files/ocs-ci/$PLATFORM/ocpdr ]; then
		yq -y -i '.RUN.ocpdr = "ocpdr"' $WORKSPACE/ocs-ci-conf.yaml
	fi

	if [ "$PLATFORM" == powervs ]; then
		yq -y -i '.ENV_DATA.number_of_storage_disks = 8' $WORKSPACE/ocs-ci-conf.yaml

		# ocs-ci powervs support uses ssh to restart nodes.  Since ocs-ci runs locally
		# and the cluster is in the cloud, the bastion ip is needed as a jump server
		# to connect with master and worker nodes.

		if [ -e $WORKSPACE/.bastion_ip ]; then
			source $WORKSPACE/.bastion_ip
		fi

		# Set bastion ip in the ocs-ci-conf.yaml

		if [ -n "$BASTION_IP" ]; then
			yq -y -i '.ENV_DATA.bastion_ip |= env.BASTION_IP' $WORKSPACE/ocs-ci-conf.yaml
		fi
	fi

}

function terraform_apply () {
	export TF_LOG=TRACE
	export TF_LOG_PATH=$WORKSPACE/terraform.log
	cat $WORKSPACE/ocs-upi-kvm/files/$PLATFORM/site.tfvars.in | envsubst > $WORKSPACE/site.tfvars
	echo "site.tfvars:"
	cat $WORKSPACE/site.tfvars
	$WORKSPACE/bin/terraform apply -var-file var.tfvars -var-file $WORKSPACE/site.tfvars -auto-approve -parallelism=7
}
