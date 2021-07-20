#!/bin/bash

#Set this variable to true to collect must-gather logs
export MUST_GATHER=${MUST_GATHER:=false}

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
echo "Print node status"

oc get nodes
echo "Checking ceph pod failures"

#switch to openshift-storage namespace
oc project openshift-storage

ceph_pods=( $(oc get pods | grep rook-ceph | awk {'print $1'}) )
pod_status=( $(oc get pods | grep rook-ceph | awk {'print $3'}) )

rm -rf $WORKSPACE/debug-ceph-pods-logs
mkdir $WORKSPACE/debug-ceph-pods-logs
log=$WORKSPACE/debug-ceph-pods-logs/debug-ceph-pods.log

count=1
for ((i=0; i<="${#pod_status[@]}"; i++))
do
    if [[ ${pod_status[$i]} == "Error" || ${pod_status[$i]} == "CrashLoopBackOff" ]]
    then
        echo "$count. ${ceph_pods[$i]} " | tee -a $log
        containers=( $(oc get pod ${ceph_pods[$i]} -o jsonpath={.spec.containers[*].name}) )
        echo "Containers running in this pod: ${containers[*]}" | tee -a $log
        echo | tee -a $log
        for ((j=0; j<"${#containers[@]}"; j++))
        do
                container_status=`oc get pod ${ceph_pods[$i]} -o jsonpath={.status.containerStatuses[$j].ready}`
                container_name=`oc get pod ${ceph_pods[$i]} -o jsonpath={.status.containerStatuses[$j].name}`
                if [[ $container_status == "false" ]]
                then
                        echo "Failing containers: $container_name"  | tee -a $log
                        echo  | tee -a $log
                        echo "State: "  | tee -a $log
                        oc get pod ${ceph_pods[$i]} -o jsonpath={.status.containerStatuses[$j].state}  | tee -a $log
                        echo  | tee -a $log
                        echo  | tee -a $log
                else
                        continue
                fi
                echo "Pod Events:"  | tee -a $log
                oc describe pod  ${ceph_pods[$i]} | awk '/Events/{y=1;next}y'  | tee -a $log
        done
        count=$((count+1))
        echo  | tee -a $log
        echo "------------------------------------------------------------------------------------------------------------------------"  | tee -a $log
    fi
done

if [[ $count == 1 ]]
then
        echo "There are no ceph pods in Error and CrashLoopBackoff state"
        rm -rf $WORKSPACE/debug-ceph-pods-logs
        exit
fi

#Collect must-gather logs if MUST_GATHER=true
if [[ $MUST_GATHER == "true" ]]
then
    echo "Collecting must-gather logs"  | tee -a $log
    echo | tee -a $log
    mkdir $WORKSPACE/debug-ceph-pods-logs/must-gather
    ocs_operator=`oc get csv | grep ocs-operator | awk {'print $1'}`
    OCS_VERSION=`oc get csv $ocs_operator -o jsonpath={.spec.version} | cut -c1-3`
    oc adm must-gather --image=quay.io/rhceph-dev/ocs-must-gather:latest-$OCS_VERSION --dest-dir=$WORKSPACE/debug-ceph-pods-logs/must-gather | tee -a $log
fi

