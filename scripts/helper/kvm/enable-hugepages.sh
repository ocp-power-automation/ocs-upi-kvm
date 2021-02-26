#!/bin/bash

# Tune memory management for worker VMs

# WORKER_DESIRED_MEM x WORKERS in gigabytes must be available in the hugepage pool.

# By default, 256 GBs of huge pages are allocated in huge page pool.  

# You must reboot your server for the changes to take affect.

if [ "$( whoami )" != "root" ]; then
    echo "ERROR: This script must be invoked by root"
    exit 1
fi

if [ ! -e helper/parameters.sh ]; then
        echo "ERROR: This script should be invoked from the directory ocs-upi-kvm/scripts"
        exit 1
fi
source helper/parameters.sh

hugePagePoolBytes=$(( HUGE_PAGE_POOL_TOTAL * 1024 * 1024 * 1024 ))
numHugePages=$(( hugePagePoolBytes / HugePageBytes ))

NumHugePagesPool=$(cat /proc/meminfo | grep HugePages_Total | awk '{print $2}')
if [ "$NumHugePagesPool" != "0" ]; then
	echo "ERROR: Huge Page Pool already allocated.  Number of hugepages should be set to $numHugePages"
	echo "Edit /etc/default/grub and /etc/sysctl.conf, invoke grub2-mkconfig, and reboot"
	exit 1
fi

grep hugepages /etc/default/grub
if [ "$?" == 0 ]; then
	echo "ERROR: Huge Page Pool already allocated via /etc/default/grub.  Number of hugepages should be set to $numHugePages"
	echo "Edit /etc/default/grub and /etc/sysctl.conf, invoke grub2-mkconfig, and reboot"
	exit 1
fi

yum -y install numactl

systemctl stop ksm
systemctl stop ksm
systemctl disable ksmtuned
systemctl disable ksm

echo "Updating kernel boot parameters in /etc/default/grub"

sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"default_hugepagesz=$HugePageSize hugepages=$numHugePages /" /etc/default/grub
grub2-mkconfig > /boot/grub2/grub.cfg

grep "vm.nr_hugepages" /etc/sysctl.conf
if [ "$?" != 0 ]; then
	echo "vm.nr_hugepages = $numHugePages" >> /etc/sysctl.conf
	sysctl -p
else
	echo "Please ensure 'vm.nr_hugepages = "$numHugePages"' or greater in /etc/sysctl.conf"
fi

echo "Please reboot"
