#!/bin/bash
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
#Copy Right IBM

VERSION="202010191400";
#================================================================================
# this shell script will be launched by a cron job.
# It lives in /test.
# Some notes on how it works
# - Verify that the /home/test exists. if not print warning and continue execution
# - If not the right account send warning message.
#================================================================================
# Some variables here:
export TESTDIR="/home/test/" #This is where we expect the directory for the Auto Testing
export LOGDIR="/home/test/logs/" #Dir for the logs.
export LOGDATE=`date "+\%d\%H\%M"`
export TESTUSR="test" # Test User

# Before launching the steps we need to check prerequisites and credentials:
#  set -x #comment out or remove this once the script is ready for delivery. 
# We need to make sure that the test directory for the test account exists.
# /home/test
# If it doesn't exist then use the current dir (pwd).
if [[ ! -d $TESTDIR ]]
then
    #Send warning and continue. Use the current directory (pwd).
    echo "---------------------------------------------------------"
    echo "The automation assumes the existance of a test account."
    echo "The test account must have /home/test as its home dir."
    echo "please create it or have a system administrator create it."
    echo "The test account must have sudo priviliges."
    echo "---------------------------------------------------------"
    TESTDIR=$( pwd )
    LOGDIR="$TESTDIR/logs/"
fi
echo "---------------------------------------------------------"
echo "using $TESTDIR for output."
echo "---------------------------------------------------------"
#check if we are the account required or an account with priviliges to do it.
if [ "$TESTUSR" != "$( whoami )" ]
then
    echo "---------------------------------------------------------"
    echo "this is not the test account."
    echo "---------------------------------------------------------"
    #there is a posibility that this account is root. check this first:
    if [ "$( whoami )" == "root" ]
    then
        echo "---------------------------------------------------------"
        echo "this is the root account."
        echo "We do not recommend using this account for the autotest launch"
        echo "it is highly recomended to use the test account"
        echo "---------------------------------------------------------"
    else
        TESTUSR=$( whoami )
        echo "---------------------------------------------------------"
        echo "if $TESTUSR does not have all the expected priviliges the test will fail."
        echo "---------------------------------------------------------"
    fi
else
    echo "---------------------------------------------------------"
    echo "test account verified"
    echo "---------------------------------------------------------"
fi

#check that the logs dir exists.
if [[ ! -d $LOGDIR ]]
then
    echo "---------------------------------------------------------"
    echo "Generating the logs directory."
    echo "---------------------------------------------------------"
    mkdir $LOGDIR 
fi

echo "---------------------------------------------------------"
echo "Checking of ocs-upi-kvm already present"
if [[ -d ocs-upi-kvm  ]]
then
        echo "ocs-upi-kvm already present. Removing it"
        rm -rf ocs-upi-kvm
fi
echo "---------------------------------------------------------"

echo "---------------------------------------------------------"
echo "Cloning ocs-upi-kvm with recursive"
git clone https://github.com/ocp-power-automation/ocs-upi-kvm
echo "---------------------------------------------------------"

# From this point I assume that any environment variable, including the required ones exist.
# I also assume that the auth.yaml and the pull-secrets.txt files exist directly under /home/test

#set +x #stop debugging.

echo "---------------------------------------------------------"
echo "Invoking OCP/OCS deploy and run tier 2 and 3 tests"
echo "---------------------------------------------------------"

if [ ! -e ~/test-chron-ocs.sh ]
then
    cp ./ocs-upi-kvm/samples/test-chron-ocs.sh ~
fi

# Modify test-cron-ocs.sh to specify custom tier test parameters and the environment
# variables like RHID USERID and PASSWORD and IMAGES_PATH

./test-chron-ocs.sh --latest-ocs

echo "---------------------------------------------------------"
echo "Complete."
echo "---------------------------------------------------------"

