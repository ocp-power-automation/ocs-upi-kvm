#!/bin/bash

# Run named ocs-ci tier test on previously created OCP cluster

# TODO: Add support for individual test runs -- a specific test in a tier

arg1=$1

if [[ "$arg1" =~ "help" ]] || [ "$arg1" == "-?" ] ; then
	echo "Usage: test-ocs-ci.sh [{ --tier 0,1,2,3,4,4a,4b,4c | --performance | --workloads | --scale | ... }]"
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
		echo "Usage: test-ocs-ci.sh [{ --tier 0,1,2,3,4,4a,4b,4c | --performance | --workloads | --scale | ... }]"
		echo "Expecting -- to precede argument, run-ci '-m xxx' is specified as test-ocs-ci.sh --xxx"
		exit 1
	else
		ocsci_cmd="${arg1//\-/}"
	fi
fi

if [ ! -e helper/parameters.sh ]; then
	echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

source helper/parameters.sh

export PATH=$WORKSPACE/bin:$PATH
export KUBECONFIG=$WORKSPACE/auth/kubeconfig

pushd ../src/ocs-ci

source $WORKSPACE/venv/bin/activate		# enter 'deactivate' in venv shell to exit

# Create supplemental config if it doesn't exist.  User may edit file after ocs deploy

export LOGDIR=$WORKSPACE/logs-ocs-ci/$OCP_VERSION
if [ ! -e $WORKSPACE/ocs-ci-conf.yaml ]; then
        cp ../../files/ocs-ci-conf.yaml $WORKSPACE/ocs-ci-conf.yaml
        mkdir -p $LOGDIR
        yq -y -i '.RUN.log_dir |= env.LOGDIR' $WORKSPACE/ocs-ci-conf.yaml
fi

# Relate the report generated below with the ocs-ci deployment via run_id 

run_id=$(ls -t -1 $LOGDIR/run*.yaml | head -n 1 | xargs grep run_id | awk '{print $2}')

if [[ -n "${tests[@]}" ]]; then
	for i in "${tests[@]}"
	do
		pytest --junitxml=$LOGDIR/test_results.xml

		echo "========================================================================================="
		echo "============================= run-ci -m \"tier$i and manage\" ============================="
		echo "========================================================================================="

		set -x
		time run-ci -m "tier$i and manage" --cluster-name ocstest \
			--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
			--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
		        --cluster-path $WORKSPACE --collect-logs \
			--self-contained-html --junit-xml $LOGDIR/test_results.xml \
			--html $LOGDIR/tier${i}_${run_id}_report.html tests/
		rc=$?
		set +x
		echo "TEST RESULT: run-ci tier$i rc=$rc"
	done
else
	echo "========================================================================================="
	echo "============================= run-ci -m \"$ocsci_cmd\" ============================="
	echo "========================================================================================="

	pytest --junitxml=$LOGDIR/test_results.xml

	set -x
	time run-ci -m "$ocsci_cmd" --cluster-name ocstest \
		--ocsci-conf conf/ocsci/production_powervs_upi.yaml \
		--ocsci-conf $WORKSPACE/ocs-ci-conf.yaml \
		--cluster-path $WORKSPACE --collect-logs \
		--self-contained-html --junit-xml $LOGDIR/test_results.xml \
		--html $LOGDIR/test_${ocsci_cmd}_${run_id}_report.html tests/
	rc=$?
	set +x
	echo "OCS-CI $ocsci_cmd RESULT: run-ci rc=$rc"
fi

deactivate

popd
