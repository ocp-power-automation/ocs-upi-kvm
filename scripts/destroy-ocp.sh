#!/bin/bash

set -e

if [ ! -e helper/parameters.sh ]; then
	echo "Please invoke this script from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

if [ "$PLATFORM" == "kvm" ]; then
	sudo -sE helper/kvm/virsh-cleanup.sh
else
	pushd ../src/$OCP_PROJECT

	if [ ! -e terraform.tfstate ]; then
		echo "No terraform artifacts or state file!"
		exit 0
	fi

	terraform_cmd=$WORKSPACE/bin/terraform

	if [[ $($terraform_cmd state list -state=terraform.tfstate | wc -l) -eq 0 ]]; then
		echo "Nothing to destroy!"
	else
		set +e

		echo "Validating cluster to be deleted is network addressible ..."
		bastion_ip=$($terraform_cmd output | grep ^bastion_public_ip | awk '{print $3}')
		if [ -n "$bastion_ip" ]; then
		
			echo "Validate use of oc command for ocs-ci teardown ..."

			source $WORKSPACE/env-ocp.sh
			oc get nodes
			rc=$?
			if [ "$rc" != 0 ]; then
				echo "Retry 1 of 2 - oc command ..."
				sleep 5m
				oc get nodes
				rc=$?
			fi
			if [ "$rc" != 0 ]; then
				echo "Retry 2 of 2 - oc command ..."
				sleep 15m
				oc get nodes
				rc=$?
			fi

			if [ "$rc" == 0 ]; then
				pushd ../../scripts
				echo "Invoking teardown-ocs-ci.sh"
				./teardown-ocs-ci.sh
				popd
			fi

			echo "Invoking terraform destroy"
			$terraform_cmd destroy -var-file $WORKSPACE/site.tfvars -auto-approve -parallelism=3

			echo "Removing $bastion_ip from /etc/hosts"
			grep -v "$bastion_ip" /etc/hosts | tee /tmp/hosts.1
			sudo mv /tmp/hosts.1 /etc/hosts
		else
			echo "Could not determine bastion_id.  Terraform state is incomplete"
		fi

		rm -f terraform.tfstate

		set -e
	fi

	rm -rf .terraform

	popd
fi
