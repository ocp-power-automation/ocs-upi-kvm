#!/bin/bash

# Run named ocs-ci tier test on previously created OCP cluster

# TODO: Add support for individual test runs -- a specific test in a tier

arg1=$1

COUNT="${RERUN_TIER_TEST:-1}"

if [[ "$arg1" =~ "help" ]] || [ "$arg1" == "-?" ] ; then
	echo "Usage: test-ocs-ci.sh [{ --tier 0,1,2,3,4,4a,4b,4c | --workloads | --scale | ... }]"
        echo "No arguments is the same as --tier 0,1"
	exit 1
fi

if [ -z "$arg1" ]; then
	tests=('0' '1')
else
	if [[ "$arg1" == "--tier" ]]; then
		tests=$2
		if [ -z "$tests" ]; then
			echo "Usage: test-ocs-ci.sh [--tier 0,1,2,3,4,4a,4b,4c ]"
        		echo "No arguments is the same as --tier 0,1"
			exit 1
		fi
		tests=($(echo $tests | sed 's/,/ /g'))
		for i in "${tests[@]}"
		do
			if [[ ! "0 1 2 3 4 4a 4b 4c" =~ "$i" ]]; then
				echo "ERROR: $0 invalid test tier: $i"
				exit 1
			fi
		done
	elif [[ ! "$arg1" =~ ^-- ]]; then
		echo "Usage: test-ocs-ci.sh [{ --tier 0,1,2,3,4,4a,4b,4c | --workloads | --scale | ... }]"
		echo "Expecting -- to precede argument, run-ci '-m xxx' is specified as test-ocs-ci.sh --xxx"
		exit 1
	else
		ocsci_cmd="${arg1//\-/}"
		if [[ "$ocsci_cmd" =~ performance ]]; then
			echo "ERROR: $0 invalid argument --performance.  Try dev-ocs-perf.sh or test-ocs-perf.sh"
			exit 1
		fi
	fi
fi

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

export LOGDIR_BASE=logs-ocs-ci
export LOGDIR_INSTANCE=$LOGDIR_BASE/$OCS_VERSION

if [ "$OCS_CI_ON_BASTION" == true ]; then
	invoke_ocs_ci_on_bastion $0 $@

	# Copy testcase logs and html report
	mkdir -p $WORKSPACE/$LOGDIR_BASE
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r root@$BASTION_IP:$LOGDIR_INSTANCE $WORKSPACE/$LOGDIR_BASE

	exit $ocs_ci_on_bastion_rc
fi

export LOGDIR=$WORKSPACE/$LOGDIR_INSTANCE
mkdir -p $LOGDIR

export PATH=$WORKSPACE/bin:$PATH

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

source $WORKSPACE/venv/bin/activate		# enter 'deactivate' in venv shell to exit

# Create supplemental config if it doesn't exist.  User may edit file after ocs deploy

if [ ! -e $WORKSPACE/ocs-ci-conf.yaml ]; then
        cp ../../files/os-ci/ocs-ci-conf.yaml $WORKSPACE/ocs-ci-conf.yaml
	update_supplemental_ocsci_config
fi

# Relate the report generated below with the ocs-ci deployment via run_id 

run_id=$(ls -t -1 $LOGDIR/run*.yaml | head -n 1 | xargs grep run_id | awk '{print $2}')

echo -e "\nSupplemental ocs-ci config:"
cat $WORKSPACE/ocs-ci-conf.yaml
echo

export SANITIZED_OCP_VERSION=${OCP_VERSION/./}
export SANITIZED_OCS_VERSION=${OCS_VERSION/./}

if [[ -n "${tests[@]}" ]]; then
	for i in "${tests[@]}"
	do
		echo "========================================================================================="
		echo "================================ run-ci -m \"tier$i\" ==================================="
		echo "========================================================================================="

		set +x
		for j in $(seq "${COUNT}"); do
			echo  "Running tier${i}, iteration ${j}"
			html_fname=tier${i}_ocp${SANITIZED_OCP_VERSION}_ocs${SANITIZED_OCS_VERSION}_${PLATFORM}_${run_id}_report_${j}.html
			set -x
			time run-ci -m "tier$i" --cluster-name ocstest --last-failed \
				--ocp-version $OCP_VERSION --ocs-version=$OCS_VERSION \
				--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
				--ocsci-conf conf/ocsci/lso_enable_rotational_disks.yaml \
				--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
				--cluster-path $WORKSPACE --collect-logs \
				--self-contained-html --junit-xml $LOGDIR/test_results_tier${i}_$j.xml \
				--html $LOGDIR/$html_fname tests/
			rc=$?
			set +x
			echo "Sleeping for things to settle down ";sleep 600
		done
		pytest_html_merger -i /root/logs-ocs-ci/4.12/ -o "$LOGDIR/results.html"
		echo -e "\n=> Test result: run-ci tier$i rc=$rc html=$LOGDIR/results.html"
	done
else
	echo "========================================================================================="
	echo "============================= run-ci -m \"$ocsci_cmd\" =================================="
	echo "========================================================================================="

	# pytest --junitxml=$LOGDIR/test_results.xml

	html_fname=${ocsci_cmd}_ocp${SANITIZED_OCP_VERSION}_ocs${SANITIZED_OCS_VERSION}_${PLATFORM}_${run_id}_report.html

	set -x
	time run-ci -m "$ocsci_cmd" --cluster-name ocstest \
		--ocp-version $OCP_VERSION --ocs-version=$OCS_VERSION \
		--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
		--ocsci-conf conf/ocsci/lso_enable_rotational_disks.yaml \
		--ocsci-conf conf/ocsci/manual_subscription_plan_approval.yaml \
		--ocsci-conf conf/examples/monitoring.yaml \
		--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
		--cluster-path $WORKSPACE --collect-logs \
		--self-contained-html --junit-xml $LOGDIR/test_results.xml \
		--html $LOGDIR/$html_fname tests/
	rc=$?
	set +x
	echo -e "\n=> Test result: run-ci $ocsci_cmd rc=$rc html=$html_fname"
fi

deactivate

popd
