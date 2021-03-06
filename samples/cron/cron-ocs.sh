#!/bin/bash
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
#Copy Right IBM

# Check if another instance of the same script is running, if so quit.

CRONOCS="test-cron-ocs"

ps -edf | grep -v grep | grep $CRONOCS > /dev/null
if [ "$?" == 0 ]; then
    echo "$CRONOCS is running. Wait for it to complete before starting again."
    exit 1
fi
echo "$CRONOCS stopped"

if [ "$( whoami )" == "root" ]; then
    echo "This is the root account which is not allowed for this cron job" 
    exit 1
fi

if [[ ! -e auth.yaml ]] || [[ ! -e pull-secret.txt ]] || [[ ! -e $CRONOCS.sh ]]; then
    echo "At least one required file is missing: auth.yaml, pull-secret.txt, $CRONOCS.sh"
    exit 1
fi

echo "Preparing environment"

DIR=$(pwd)
export LOGDIR="$DIR/logs-cron"
export LOGDATE=$(date "+%d%H%M")

mkdir -p $LOGDIR

echo "Cloning project ocs-upi-kvm..."

rm -rf ocs-upi-kvm
git clone https://github.com/ocp-power-automation/ocs-upi-kvm

echo "Run ocs-ci tier tests in the background...  Log files in $LOGDIR"

./$CRONOCS.sh
