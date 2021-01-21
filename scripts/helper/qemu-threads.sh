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

type numastat > /dev/null
if [ "$?" == 0 ]; then
	sudo numastat -c qemu
fi
