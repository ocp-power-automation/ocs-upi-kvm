#!/bin/bash

interval=30m
cnt=1

nargs=$#
i=1
while (( $i <= $nargs ))
do
	arg=$1
	case "$arg" in
	--interval)
		shift
		interval=$1
		shift
		(( i = i + 2 ))
		;;
	--cnt)
		shift
		cnt=$1
		shift
		(( i = i + 2 ))
		;;
	*)
		echo "Usage: $0 [ --interval <delay> ] [ --cnt <iterations> ]"
		echo "Defaults are delay=30m cnt=1"
		exit 1
		;;
	esac
done

if [ ! -e helper/parameters.sh ]; then
	echo "ERROR: This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

export WORKSPACE=../..

if [ ! -e "$WORKSPACE/env-ocp.sh" ]; then
	echo "ERROR: env-ocp.sh not found.  oc command not available"
	exit 1
fi

source $WORKSPACE/env-ocp.sh


oc get clusterversion
echo
oc get csv -A
echo

while :
do
	echo -e "\n------------------- $(date) -------------------\n"

	oc get nodes
	echo
	oc adm top nodes 2>/dev/null
	echo
	oc get pods -n openshift-storage
	echo
	oc adm top pods -n openshift-storage 2>/dev/null
	echo
	oc adm top pods -n elastic 2> /dev/null

	cnt=$(( cnt - 1 ))
	if (( cnt <= 0 )); then
		break
	fi

	sleep $interval

done
