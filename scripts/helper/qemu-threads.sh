#!/bin/bash

pids=( $(ps -edf | grep ^qemu | awk '{print $2}') )

workers=( $(ps -edf | grep ^qemu | awk '{print $10}') )

j=0
for i in "${pids[@]}"
do
	worker=${workers[j]/,debug-threads=on/}
	echo --------------------- $worker
	echo 
	ps -T --pid $i --ppid 2 -o pid,uname,comm,tid,cpuid,pri,time,pcpu | egrep 'USER|qemu|vhost-'$i
	echo
	echo
	((j++))
done

type numastat > /dev/null 2>&1
if [ "$?" == 0 ]; then
	sudo numastat -c qemu
fi

echo -e "\nhost kvm server"
ssh root@192.168.88.2 uptime
ssh root@192.168.88.2 vmstat -w

echo -e "\nbastion-$j"
ssh root@192.168.88.2 uptime
ssh root@192.168.88.2 vmstat -w

j=0
for i in 192.168.88.4 192.168.88.5 192.168.88.6
do
	echo -e "\nmaster-$j"
	ssh -o StrictHostKeyChecking=no core@$i uptime
	ssh -o StrictHostKeyChecking=no core@$i vmstat -w
	((j++))
done

j=0
for i in 192.168.88.21 192.168.88.22 192.168.88.23
do
	echo -e "\nworker-$j"
	ssh -o StrictHostKeyChecking=no core@$i uptime
	ssh -o StrictHostKeyChecking=no core@$i vmstat -w
	((j++))
done
