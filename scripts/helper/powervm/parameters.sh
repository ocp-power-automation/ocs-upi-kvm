#!/bin/bash

export PVC_URL=${PVC_URL:=https://scnlpowercloud.pok.stglabs.ibm.com:5000/v3/}
export PVC_TENANT=${PVC_TENANT:=icp-test}
export PVC_DOMAIN=${PVC_DOMAIN:=Default}
export PVC_SUBNET_NAME=${PVC_SUBNET_NAME:=icp_network2}
export PVC_SUBNET_TYPE=${PVC_SUBNET_TYPE:=SEA}

export BASTION_COMPUTE_TEMPLATE=${BASTION_COMPUTE_TEMPLATE:=ocp4-qa-bastion}
export BOOTSTRAP_COMPUTE_TEMPLATE=${BOOTSTRAP_COMPUTE_TEMPLATE:=ocp4-qa-bootstrap}
export MASTER_COMPUTE_TEMPLATE=${MASTER_COMPUTE_TEMPLATE:=medium}
export WORKER_COMPUTE_TEMPLATE=${WORKER_COMPUTE_TEMPLATE:=large}

if [ -z "$CLUSTER_ID_PREFIX" ]; then
	CLUSTER_ID_PREFIX=rdr-${RHID_USERNAME:0:3}
	export CLUSTER_ID_PREFIX=$CLUSTER_ID_PREFIX${OCP_VERSION/./}
fi

export CMA_PERCENT=${CMA_PERCENT:=0}					# Kernel contiguous memory area for DMA

# The boot images below are common across OCS development zones, except where noted

export BASTION_IMAGE=${BASTION_IMAGE:=6d9e7fc7-ae10-463c-b3bf-14ee6ff3647a}

case $OCP_VERSION in
4.4|4.5)
	export RHCOS_IMAGE=${RHCOS_IMAGE:=ca2f9631-9fd3-4fa5-b349-3e93dd057d46}   # cicd-rhcos-45.82.202007072057-0-openstack.ppc64le
	export OCP_PROJECT_COMMIT=origin/release-4.5
	;;
4.6)
	export RHCOS_IMAGE=${RHCOS_IMAGE:=a08e13ae-897b-4ce1-b945-80c3b59fcc86}   # rhcos-46.82.20200918070611-0-openstack.ppc64le
	export OCP_PROJECT_COMMIT=origin/release-4.6
	export INSTALL_PLAYBOOK_TAG=e89bef76cec089a481d6de2b7fa07944ae0481a5      # Align with powervs.  Was 1 commit down level
	;;
4.7)
	export RHCOS_IMAGE=${RHCOS_IMAGE:=ad1e6a7e-02f3-4253-994a-985bb548f9ec}   # cicd-rhcos-47.0.20210216-rc2-openstack.ppc64le 
	export OCP_PROJECT_COMMIT=origin/release-4.7
	export INSTALL_PLAYBOOK_TAG=86b12e097f430dca95a151cb1073c1b1f07be024	  # Align with powervs.  Was 7 commits down level
	;;
4.8)
	export RHCOS_IMAGE=${RHCOS_IMAGE:=09e18a43-8440-40f2-abe6-b8824fb679cd}   # rhcos-48.84.202105130819-0-openstack.ppc64le
	;;
esac

export WORKER_VOLUME_SIZE=${WORKER_VOLUME_SIZE:="500"}

export DNS_FORWARDERS=${DNS_FORWARDERS:="1.1.1.1; 9.9.9.9"}
if [[ ! "$DNS_FORWARDERS" =~ "$DNS_BACKUP_SERVER" ]]; then
	export DNS_FORWARDERS="$DNS_FORWARDERS; $DNS_BACKUP_SERVER"
fi

export CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="ibm.com"}			# xip.io

export OCS_CI_ON_BASTION=${OCS_CI_ON_BASTION:="false"}			# ocs-ci runs locally by default

########################### Internal variables & functions #############################


# IMPORTANT: Increment POWERVM_SETUP_GENCNT if the powervs_setup_host.sh file changes
#            Increments by more than 2 will rebuild terraform modules also.  ie. 1->4

POWERVM_SETUP_GENCNT=1

OCP_PROJECT=ocp4-upi-powervm

# List of OCS DNS Entries to be added to /etc/hosts.  List is separated by spaces

OCS_DNS_ENTRIES="noobaa-mgmt-openshift-storage s3-openshift-storage rgw"

function prepare_new_cluster_delete_old_cluster () {

	POWERVS_SETUP_GENCNT_INSTALLED=-1

	invoke_powervm_setup=false
	if [ ! -e ~/.powervm_setup ]; then
		invoke_powervm_setup=true
	else
		source ~/.powervm_setup
		if [[ "$POWERVM_SETUP_GENCNT_INSTALLED" -lt "$POWERVM_SETUP_GENCNT" ]]; then
			invoke_powervm_setup=true
		fi
	fi

        if [ "$invoke_powervm_setup" == true ]; then
                echo "Invoking setup-powervm-client.sh"
                sudo -sE helper/powervm/setup-powervm-client.sh
                echo "POWERVM_SETUP_GENCNT_INSTALLED=$POWERVM_SETUP_GENCNT" > ~/.powervm_setup
        fi

        # Remove pre-existing cluster.  We are going to create a new one

        echo "Invoking destroy-ocp.sh"
	./destroy-ocp.sh
}

# This is invoked at the end of ocp cluster create

function setup_remote_oc_use () {
	pushd $WORKSPACE/ocs-upi-kvm/src/$OCP_PROJECT

	terraform_cmd=$WORKSPACE/bin/terraform

	# BASTION_IP is used by caller.   bastion_public_ip on powervs

	BASTION_IP=$($terraform_cmd output | grep ^bastion_ip | awk '{print $3}')

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

		echo "export BASTION_IP=$BASTION_IP" > $WORKSPACE/.bastion_ip
		echo "export PLATFORM=$PLATFORM" >> $WORKSPACE/.bastion_ip
	else
		echo "No terraform data for local oc setup"
		exit 1
	fi

	popd
}

# This is invoked at the start of setup-ocs-ci.sh

function setup_remote_ocsci_use () {
	source $WORKSPACE/.bastion_ip

	if [[ "$OCS_CI_ON_BASTION" == "true" ]] && [[ -n "$BASTION_IP" ]]; then

		echo "Copy ocs-ci secrets to bastion node $BASTION_IP"

		cat $WORKSPACE/ocs-upi-kvm/files/$PLATFORM/env-ocs-ci.sh.in | envsubst > $WORKSPACE/bastion-env-ocs-ci.sh
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/bastion-env-ocs-ci.sh root@$BASTION_IP:env-ocs-ci.sh >/dev/null 2>&1
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/pull-secret.txt root@$BASTION_IP: >/dev/null 2>&1
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/auth.yaml root@$BASTION_IP: >/dev/null 2>&1

		BASTION_CMD="mkdir -p ~/bin && cp /usr/local/bin/oc ~/bin"
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP $BASTION_CMD >/dev/null 2>&1
		BASTION_CMD="cp -r openstack-upi/auth ~"
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP $BASTION_CMD >/dev/null 2>&1

		echo "Copy ocs-upi-kvm to bastion node $BASTION_IP"

		pushd $WORKSPACE
		tar -zcvf bastion-ocs-upi-kvm.tar.gz ocs-upi-kvm >/dev/null 2>&1
		popd
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP rm -rf ocs-upi-kvm >/dev/null 2>&1
		scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $WORKSPACE/bastion-ocs-upi-kvm.tar.gz root@$BASTION_IP: >/dev/null 2>&1
		BASTION_CMD="tar -xvzf bastion-ocs-upi-kvm.tar.gz >/dev/null 2>&1"
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP $BASTION_CMD >/dev/null 2>&1
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$BASTION_IP chown -R root:root ocs-upi-kvm >/dev/null 2>&1
	fi
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

function config_ceph_for_nvmessd ()
{
	ceph_tools=$( oc -n openshift-storage get pods | grep rook-ceph-tools | awk '{print $1}' )

	set +e
	oc -n openshift-storage rsh $ceph_tools ceph config dump 2>&1 | grep osd_op_num_threads_per_shard > /dev/null
	rc=$?
	set -e

	if [ "$rc" == 0 ]; then
		echo "Ceph configuration:"
		oc -n openshift-storage rsh $ceph_tools ceph config dump
		return
	fi

	echo "Performing ceph configuration nvme/ssd enhancements"

	# TODO Add check for pre-existing settings and don't update.  These are new settings
	# TODO Does this apply to powervm?

	oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_op_num_threads_per_shard 2
	oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_op_num_shards 8
	oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_recovery_sleep 0
	oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_snap_trim_sleep 0
	oc -n openshift-storage rsh $ceph_tools ceph config set osd osd_delete_sleep 0
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_min_alloc_size 4K
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_prefer_deferred_size 0
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_compression_min_blob_size 8K
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_compression_max_blob_size 64K
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_max_blob_size 64K
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_cache_size 3G
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_throttle_cost_per_io 4000
	oc -n openshift-storage rsh $ceph_tools ceph config set osd bluestore_deferred_batch_ops 16

	echo "Dumping ceph configuration after nvme/ssd enhancements"

	oc -n openshift-storage rsh $ceph_tools ceph config dump

	# Delay a little for new settings to take effect

	sleep 1m
}

