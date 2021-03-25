#!/bin/bash

export PVS_API_KEY=${PVS_API_KEY:=""}					# Obtained from CLI - ibmcloud pi service-list
export PVS_REGION=${PVS_REGION:="lon"}
export PVS_ZONE=${PVS_ZONE:="lon06"}
export PVS_SERVICE_INSTANCE_ID=${PVS_SERVICE_INSTANCE_ID:=""}

export PVS_SUBNET_NAME=${PVS_SUBNET_NAME:="ocp-net"}

export SYSTEM_TYPE=${SYSTEM_TYPE:="s922"}				# The type of system (s922/e980)
export PROCESSOR_TYPE=${PROCESSOR_TYPE:="shared"}			# The type of processor mode (shared/dedicated)

if [ -z "$CLUSTER_ID_PREFIX" ]; then
	CLUSTER_ID_PREFIX=${RHID_USERNAME:0:6}
	export CLUSTER_ID_PREFIX=$CLUSTER_ID_PREFIX${OCP_VERSION/./}
fi

# Check service instance first, since it is not set above to a default value.  It
# over rides zone and region if the service instance is set and recognized

if [ "$PVS_SERVICE_INSTANCE_ID" == fac4755e-8aff-45f5-8d5c-1d3b58b7a229 ]; then
	PVS_REGION=lon
	PVS_ZONE=lon06
elif [ "$PVS_SERVICE_INSTANCE_ID" == 60e43366-08de-4287-8c42-b7942406efc9 ]; then
	PVS_REGION=tok
	PVS_ZONE=tok04
elif [ "$PVS_REGION" == lon ] && [ "$PVS_ZONE" == lon06 ]; then
	PVS_SERVICE_INSTANCE_ID=fac4755e-8aff-45f5-8d5c-1d3b58b7a229
elif [ "$PVS_REGION" == tok ] && [ "$PVS_ZONE" == tok04 ]; then
	PVS_SERVICE_INSTANCE_ID=60e43366-08de-4287-8c42-b7942406efc9
fi

# The boot images below are common across OCS development zones, except where noted

export BASTION_IMAGE=${BASTION_IMAGE:="rhel-83-02182021"}

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

# This is default minimalistic config. For PowerVS processors are equal to entitled physical count
# So N processors == N physical core entitlements == ceil[N] vCPUs.
# Example 0.5 processors == 0.5 physical core entitlements == ceil[0.5] = 1 vCPU == 8 logical OS CPUs (SMT=8)
# Example 1.5 processors == 1.5 physical core entitlements == ceil[1.5] = 2 vCPU == 16 logical OS CPUs (SMT=8)
# Example 2 processors == 2 physical core entitlements == ceil[2] = 2 vCPU == 16 logical OS CPUs (SMT=8)

export MASTER_DESIRED_CPU=${MASTER_DESIRED_CPU:="1.25"}
export MASTER_DESIRED_MEM=${MASTER_DESIRED_MEM:="32"}
export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="1.25"}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="64"}

export VOLUME_TYPE=${VOLUME_TYPE:="tier3"}				# The volume type (ssd, standard, tier1, tier3)
export WORKER_VOLUME_SIZE=${WORKER_VOLUME_SIZE:="500"}

export DNS_FORWARDERS=${DNS_FORWARDERS:="1.1.1.1; 9.9.9.9"}
if [[ ! "$DNS_FORWARDERS" =~ "$DNS_BACKUP_SERVER" ]]; then
	export DNS_FORWARDERS="$DNS_FORWARDERS; $DNS_BACKUP_SERVER"
fi

export CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="ibm.com"}			# xip.io

############################## Validate Input Parameters ###############################

if [ -z "$PVS_API_KEY" ] || [ -z "$PVS_SERVICE_INSTANCE_ID" ]; then
	echo "Environment variables PVS_API_KEY and PVS_SERVICE_INSTANCE_ID must be set for PowerVS"
	exit 1
fi
if [ -z "$PVS_ZONE" ] || [ -z "$PVS_REGION" ]; then
	echo "Environment variables PVS_ZONE and PVS_REGION must be set for PowerVS"
	exit 1
fi

########################### Internal variables & functions #############################

# IMPORTANT: Increment POWERVS_SETUP_GENCNT if the powervs_setup_host.sh file changes
#            Increments by more than 2 will rebuild terraform modules also.  ie. 1->4

POWERVS_SETUP_GENCNT=4

OCP_PROJECT=ocp4-upi-powervs

# List of OCS DNS Entries to be added to /etc/hosts.  List is separated by spaces

OCS_DNS_ENTRIES="noobaa-mgmt-openshift-storage"

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

	# If POWERVS SETUP GENCNT increases by more than 2, rebuild terraform modules also

	if (( "$POWERVS_SETUP_GENCNT_INSTALLED" + 2 < "$POWERVS_SETUP_GENCNT" )); then
		rm -f $WORKSPACE/bin/terraform
	fi
}

function setup_remote_oc_use () {
	pushd $WORKSPACE/ocs-upi-kvm/src/$OCP_PROJECT

	terraform_cmd=$WORKSPACE/bin/terraform

	# BASTION_IP is used by caller

	BASTION_IP=$($terraform_cmd output | grep ^bastion_public_ip | awk '{print $3}')

	etc_hosts_entries=$($terraform_cmd output | awk '/^etc_hosts_entries/{getline;print;}')

	if [ -n "$BASTION_IP" ] && [ -n "$etc_hosts_entries" ]; then
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
	else
		echo "No terraform data for remote oc setup"
	fi
	popd
}
