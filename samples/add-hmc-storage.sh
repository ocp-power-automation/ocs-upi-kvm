#!/bin/bash

#Pre-reqs
  #1. openstack python client should be pre-installed on the machine where this script is run(pip install openstack-pythonclient).
  #2. OCP cluster should be already deployed

# The following variables are required to connect to the Powervc cloud. 
# Make sure you already have the powervc cert and key which is required to connect to the cloud. Provide the cert location in OS_CACERT and key location in OS_KEY
export OS_IDENTITY_API_VERSION=${OS_IDENTITY_API_VERSION:=3}
export OS_AUTH_URL=
export OS_CACERT=${OS_CACERT:="/etc/pki/tls/certs/powervc.crt"}
export OS_REGION_NAME=${OS_REGION_NAME:="RegionOne"}
export OS_PROJECT_DOMAIN_NAME=${OS_PROJECT_DOMAIN_NAME:="Default"}
export OS_PROJECT_NAME=
export OS_TENANT_NAME=$OS_PROJECT_NAME
export OS_USER_DOMAIN_NAME=${OS_USER_DOMAIN_NAME:="Default"}
export OS_KEY=${OS_KEY:="/etc/pki/tls/private/powervc.key"}

#Add your IBM intranet credentials
export OS_USERNAME=
export OS_PASSWORD=

#Add hmc login details
export HMC_IP=
export HMC_USER=
export HMC_PASS=

#T.B.D after physical disks are added to hmc - Add code to retrieve SLOT-DRC-INDEX(if we have a unique description that identifies ODF project disks) or export SLOT-DRC-INDEX 

export WORKSPACE=../..
#Check if cluster is already deployed
if [ ! -e "$WORKSPACE/env-ocp.sh" ]; then
        echo "ERROR: env-ocp.sh not found.  oc command not available"
        exit 1
fi

source $WORKSPACE/env-ocp.sh

command=$(oc get clusterversion)
if [ $? != 0 ] ; then
        echo "OCP cluster is not deployed"
        exit 1
fi

#get all details required to attach storage to lpar using hmc cli
cluster_id_prefix=`cat $WORKSPACE/site.tfvars | grep cluster_id_prefix | cut -d "=" -f 2 | tr -d ' "'`
openstack server list | grep $cluster_id_prefix | grep worker | awk {'print $4'} > worker-list
worker_count=`oc get nodes -o wide | grep worker | awk {'print $1'} | wc -l`

echo "-----------------------------------------Before attaching storage-------------------------------------------------"
i=0
while [ $i -lt $worker_count ]
do
        worker_names[$i]=$(cat worker-list | grep worker-$i)
        worker_ips[$i]=$(oc get nodes -o wide | grep worker-$i | awk {'print $6'})
        worker_lpar_names[$i]=$(openstack server show -f value -c OS-EXT-SRV-ATTR:instance_name ${worker_names[$i]})
        worker_host_serialnums[$i]=$(openstack server show -f value -c OS-EXT-SRV-ATTR:hypervisor_hostname ${worker_names[$i]} | cut -d "_" -f 2)
        worker_managed_systems[$i]=$(sshpass -p $HMC_PASS ssh -o StrictHostKeyChecking=no $HMC_USER@$HMC_IP "lssyscfg -r sys | grep ${worker_host_serialnums[$i]} |  grep -Po name=[[:alnum:]]+ | cut -d '=' -f 2 ")
		#Print output of lsblk on each worker node
        echo "-----------------------------------------lsblk output of worker-$i-------------------------------------------------"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${worker_ips[$i]} lsblk
        echo

        i=`expr $i + 1`
done

rm worker-list

#Attach storage using hmc and reboot all worker nodes
i=0
while [ $i -lt $worker_count ]
do
	#HMC storage addition
	#1. Shutdown lpar
		#chsysstate -m  ${worker_managed_systems[$i]} -r lpar -o shutdown -n ${worker_lpar_names[$i]} --immed 
	#2. Add physical disk
		#chhwres -r io -m ${worker_managed_systems[$i]} -o a -p ${worker_lpar_names[$i]} -l <SLOT-DRC-INDEX>
	#3. Activate LPAR
		#chsysstate -m ${worker_managed_systems[$i]} -r lpar -o on -n ${worker_lpar_names[$i]}
        echo "Rebooting worker-$i ..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${worker_ips[$i]} reboot
        echo

        i=`expr $i + 1`
done

#sleep for 1 min
sleep 60

#Print lsblk output after attaching storage
echo "-----------------------------------------After attaching storage-------------------------------------------------"
i=0
while [ $i -lt $worker_count ]
do
        echo "-----------------------------------------lsblk output of worker-$i-------------------------------------------------"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${worker_ips[$i]} lsblk
        echo

        i=`expr $i + 1`
done
