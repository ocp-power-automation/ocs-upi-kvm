#!/bin/bash

export PVS_API_KEY=${PVS_API_KEY:=""}					# Obtained from CLI - ibmcloud pi service-list
export PVS_REGION=${PVS_REGION:="tok"}
export PVS_ZONE=${PVS_ZONE:="tok04"}
export PVS_SERVICE_INSTANCE_ID=${PVS_SERVICE_INSTANCE_ID:=""}

export PVS_SUBNET_NAME=${PVS_SUBNET_NAME:="ocp-net"}

export SYSTEM_TYPE=${SYSTEM_TYPE:="s922"}				# The type of system (s922/e980)
export PROCESSOR_TYPE=${PROCESSOR_TYPE:="shared"}			# The type of processor mode (shared/dedicated)

if [ -z "$CLUSTER_ID_PREFIX" ]; then
	CLUSTER_ID_PREFIX=${RHID_USERNAME:0:6}
	export CLUSTER_ID_PREFIX=$CLUSTER_ID_PREFIX${OCP_VERSION/./}
fi

export USE_TIER1_STORAGE=${USE_TIER1_STORAGE:="false"}

# Check service instance first, since it is not set above to a default value.  It
# over rides zone and region if the service instance is set and recognized

if [ "$PVS_SERVICE_INSTANCE_ID" == fac4755e-8aff-45f5-8d5c-1d3b58b7a229 ]; then
	PVS_REGION=lon
	PVS_ZONE=lon06
elif [ "$PVS_SERVICE_INSTANCE_ID" == 60e43366-08de-4287-8c42-b7942406efc9 ]; then
	PVS_REGION=tok
	PVS_ZONE=tok04
elif [ "$PVS_SERVICE_INSTANCE_ID" == 481377eb-e843-46df-9afa-a815da381ffa ]; then
	PVS_REGION=sao
	PVS_ZONE=sao01
elif [ "$PVS_REGION" == lon ] && [ "$PVS_ZONE" == lon06 ]; then
	PVS_SERVICE_INSTANCE_ID=fac4755e-8aff-45f5-8d5c-1d3b58b7a229
elif [ "$PVS_REGION" == tok ] && [ "$PVS_ZONE" == tok04 ]; then
	PVS_SERVICE_INSTANCE_ID=60e43366-08de-4287-8c42-b7942406efc9
elif [ "$PVS_REGION" == sao ] && [ "$PVS_ZONE" == sao01 ]; then
	PVS_SERVICE_INSTANCE_ID=481377eb-e843-46df-9afa-a815da381ffa
fi

# The boot images below are common across OCS development zones, except where noted

export BASTION_IMAGE=${BASTION_IMAGE:="rhel-83-03192021"}

case $OCP_VERSION in
4.4|4.5)
	if [ "$PVS_REGION" == tok ] && [ "$PVS_ZONE" == tok04 ] && [ -z "$RHCOS_IMAGE" ]; then
		echo "WARNING: Validate boot image rhcos-454-09242020-001 is available in PowerVS zone ocp-ocs-tokyo-04"
		echo "WARNING: Choose PowerVS zone ocp-ocs-london-06 instead"
	fi
	export RHCOS_IMAGE=${RHCOS_IMAGE:="rhcos-454-09242020-001"}
	;;
4.6)
	export RHCOS_IMAGE=${RHCOS_IMAGE:="rhcos-46-09182020"}
	;;
4.7)
	export RHCOS_IMAGE=${RHCOS_IMAGE:="rhcos-47-02172021"}
	;;
4.8)
	export RHCOS_IMAGE=${RHCOS_IMAGE:="rhcos-48-02102021"}
	;;
*)
	echo "ERROR: OCP Version=$OCP_VERSION not supported"
	exit 1
	;;
esac

if [[ "$USE_TIER1_STORAGE" == "true" ]] && [[ ! "$BASTION_IMAGE" =~ tier1 ]] && [[ ! "$RHCOS_IMAGE" =~ tier1 ]]; then
	export BASTION_IMAGE=$BASTION_IMAGE-tier1
	export RHCOS_IMAGE=$RHCOS_IMAGE-tier1
fi

# This is default minimalistic config. For PowerVS processors are equal to entitled physical count
# So N processors == N physical core entitlements == ceil[N] vCPUs.
# Example 0.5 processors == 0.5 physical core entitlements == ceil[0.5] = 1 vCPU == 8 logical OS CPUs (SMT=8)
# Example 1.5 processors == 1.5 physical core entitlements == ceil[1.5] = 2 vCPU == 16 logical OS CPUs (SMT=8)
# Example 2 processors == 2 physical core entitlements == ceil[2] = 2 vCPU == 16 logical OS CPUs (SMT=8)

export MASTER_DESIRED_CPU=${MASTER_DESIRED_CPU:="1.25"}
export MASTER_DESIRED_MEM=${MASTER_DESIRED_MEM:="32"}
export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="1.25"}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="64"}

export WORKER_VOLUME_SIZE=${WORKER_VOLUME_SIZE:="500"}

export DNS_FORWARDERS=${DNS_FORWARDERS:="1.1.1.1; 9.9.9.9"}
if [[ ! "$DNS_FORWARDERS" =~ "$DNS_BACKUP_SERVER" ]]; then
	export DNS_FORWARDERS="$DNS_FORWARDERS; $DNS_BACKUP_SERVER"
fi

export CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="ibm.com"}			# xip.io

########################### Internal variables & functions #############################

export OCS_CI_ON_BASTION=${OCS_CI_ON_BASTION:="false"}			# ocs-ci runs locally by default

# IMPORTANT: Increment POWERVS_SETUP_GENCNT if the powervs_setup_host.sh file changes
#            Increments by more than 2 will rebuild terraform modules also.  ie. 1->4

POWERVS_SETUP_GENCNT=4

OCP_PROJECT=ocp4-upi-powervs

# List of OCS DNS Entries to be added to /etc/hosts.  List is separated by spaces

OCS_DNS_ENTRIES="noobaa-mgmt-openshift-storage s3-openshift-storage rgw"

function prepare_new_cluster_delete_old_cluster () {

	POWERVS_SETUP_GENCNT_INSTALLED=-1

	invoke_powervs_setup=false
	if [ ! -e ~/.powervs_setup ]; then
		invoke_powervs_setup=true
	else
		source ~/.powervs_setup
		if [[ "$POWERVS_SETUP_GENCNT_INSTALLED" -lt "$POWERVS_SETUP_GENCNT" ]]; then
			invoke_powervs_setup=true
		fi
	fi

        if [ "$invoke_powervs_setup" == true ]; then
                echo "Invoking setup-powervs-client.sh"
                sudo -sE helper/powervs/setup-powervs-client.sh
                echo "POWERVS_SETUP_GENCNT_INSTALLED=$POWERVS_SETUP_GENCNT" > ~/.powervs_setup
        fi

        # Remove pre-existing cluster.  We are going to create a new one

        echo "Invoking destroy-ocp.sh"
	./destroy-ocp.sh
}

function setup_remote_oc_use () {
	pushd $WORKSPACE/ocs-upi-kvm/src/$OCP_PROJECT

	terraform_cmd=$WORKSPACE/bin/terraform

	# BASTION_IP is used by caller

	BASTION_IP=$($terraform_cmd output | grep ^bastion_public_ip | awk '{print $3}')

	etc_hosts_entries=$($terraform_cmd output | awk '/^etc_hosts_entries/{getline;print;}')

	# oc command is always enabled locally

	if [[ -n "$BASTION_IP" ]] && [[ -n "$etc_hosts_entries" ]]; then
		if [ ! -e /etc/hosts.orig ]; then
			sudo cp /etc/hosts /etc/hosts.orig
		fi

		base_url=$(echo "$etc_hosts_entries" | awk '{print $2}')  # api.lbrown46-2f4f.ibm.com
		base_url=${base_url/api/apps}				  # apps.lbrown46-2f4f.ibm.com

		api_urls=( $OCS_DNS_ENTRIES )
		append_urls=$base_url
		for i in "${api_urls[@]}"
		do
			append_urls="$append_urls $i.$base_url"
		done

		echo "Adding Bastion IP $BASTION_IP to /etc/hosts"
		grep -v $BASTION_IP /etc/hosts | tee /tmp/hosts.1
		echo "$etc_hosts_entries $append_urls" >> /tmp/hosts.1
		sudo mv /tmp/hosts.1 /etc/hosts 

		# Preserve variables that are needed after cluster creation.  Mostly, by run_fio.sh

		CLUSTER_ID=$($terraform_cmd output | grep cluster_id | awk '{print $3}' | sed 's/\"//g' )
		BASTION_PRIVATE_IP=( $($terraform_cmd output | grep bastion_private_ip | awk '{print $3}' | sed 's/\./ /g' ) )
		BASTION_CIDR="${BASTION_PRIVATE_IP[0]}.${BASTION_PRIVATE_IP[1]}.${BASTION_PRIVATE_IP[2]}.0/24"
		BASTION_HTTP_PROXY="http://${CLUSTER_ID}-bastion-0:3128"

		echo "export BASTION_IP=$BASTION_IP" > $WORKSPACE/.bastion_ip
		echo "export CLUSTER_ID=$CLUSTER_ID" >> $WORKSPACE/.bastion_ip
		echo "export BASTION_PRIVATE_IP=$BASTION_PRIVATE_IP" >> $WORKSPACE/.bastion_ip
		echo "export BASTION_CIDR=$BASTION_CIDR" >> $WORKSPACE/.bastion_ip
		echo "export CLUSTER_DOMAIN=$CLUSTER_DOMAIN" >> $WORKSPACE/.bastion_ip
		echo "export BASTION_HTTP_PROXY=$BASTION_HTTP_PROXY" >> $WORKSPACE/.bastion_ip
		echo "export PLATFORM=$PLATFORM" >> $WORKSPACE/.bastion_ip
	else
		echo "No terraform data for local oc setup"
		exit 1
	fi

	# Setup ocs-ci on bastion node if specified.  Default is local server

	if [[ "$OCS_CI_ON_BASTION" == "true" ]] && [[ -n "$BASTION_IP" ]]; then
		echo "Copy ocs-ci secrets to bastion node $BASTION_IP"
		cat $WORKSPACE/ocs-upi-kvm/files/$PLATFORM/env-ocs-ci.sh.in | envsubst > $WORKSPACE/env-ocs-ci.sh
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/env-ocs-ci.sh  root@$BASTION_IP:
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/pull-secret.txt root@$BASTION_IP:
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/auth.yaml root@$BASTION_IP:

		BASTION_CMD="mkdir -p ~/bin && cp /usr/local/bin/oc ~/bin"
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP $BASTION_CMD
		BASTION_CMD="cp -r openstack-upi/auth ~"
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP $BASTION_CMD

		echo "Copy ocs-ci code with development patches to bastion node $BASTION_IP"
		pushd $WORKSPACE
		tar -zcvf bastion-ocs-upi-ci.tar.gz ocs-upi-kvm >/dev/null 2>&1
		popd
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/bastion-ocs-upi-ci.tar.gz root@$BASTION_IP:
		BASTION_CMD="tar -xvzf bastion-ocs-upi-ci.tar.gz >/dev/null 2>&1"
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP $BASTION_CMD
	fi

	popd
}

ocs_ci_on_bastion_rc=
function invoke_ocs_ci_on_bastion ()
{
	args_array=( $@ )		# Input is a variable number of tokens -- cmd arg1 arg2 arg3 ...

	cmd="${args_array[0]}"

	i=1
	n=${#args_array[@]}
	args=
	while (( i < n ))
	do
		args+="${args_array[$i]} "
		(( i++ ))
	done

	source $WORKSPACE/.bastion_ip
	BASTION_CMD="source env-ocs-ci.sh && cd ocs-upi-kvm/scripts && $cmd $args"
	echo "Invoking $BASTION_CMD on bastion node $BASTION_IP"
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP $BASTION_CMD
	ocs_ci_on_bastion_rc=$?
	echo -e "\n=> $cmd complete rc=$ocs_ci_on_bastion_rc"
}
