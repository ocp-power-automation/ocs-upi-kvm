#!/bin/bash

set -e

echo ""
echo "Virtual machines:"
echo ""
sudo -sE virsh list --all

echo ""
echo "Virtual networks:"
echo ""
sudo -sE virsh net-list --all

networks=$(sudo -sE virsh net-list --all | awk '{print $1}')
declare -i n_networks
n_networks=$(echo $networks | wc -w)-2

if [[ "$n_networks" -gt 0 ]]; then
	for i in $networks
	do
		if [[ "$i" == default ]]; then
			continue
		fi
		if [[ ! "$i" =~ ^Name ]] && [[ ! "$i" =~ ^---- ]]; then
			echo ""
			echo "VMs on network $i"
			echo ""
			sudo -sE virsh net-dhcp-leases $i
		fi
	done
fi

declare -i npools
declare -i nvols
pools=$(sudo -sE virsh pool-list --all | awk '{print $1}')
n_pools=$(echo $pools | wc -w)-2

if [[ "$n_pools" -gt 0 ]]; then
	for i in $pools
	do
		if [[ ! "$i" =~ ^Name ]] && [[ ! "$i" =~ ^---- ]]; then
			echo ""
			echo "Virtual storage pool:"
			echo ""
			sudo -sE virsh pool-info $i

			state=$(sudo virsh pool-info test-ocp4-6 | grep State | awk '{print $2}')
			if [ "$state" != inactive ]; then
				echo ""
				echo "Volumes:"
				echo ""
				sudo -sE virsh vol-list $i
			fi
		fi
	done
fi
