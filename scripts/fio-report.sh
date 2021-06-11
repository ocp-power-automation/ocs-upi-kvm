#!/bin/bash

if [ ! -e helper/parameters.sh ]; then
        echo "This script should be invoked from the directory ocs-upi-kvm/scripts"
        exit 1
fi

source helper/parameters.sh

iotype=$1
case "$iotype" in
	block|file)
		;;
	*)
		echo "Usage $0 { block | file } <fio run number>"
		echo "You must specify block or file"
		exit 1
		;;
esac

run_number=$2
if [ -z "$run_number" ]; then
	echo "Usage $0 { block | file } <fio run number>"
	echo "You must specify the fio run number.  It's located at $WORKSPACE/fio-results/$iotype"
	exit 1
fi

fiodir=$WORKSPACE/fio-results/$iotype/$run_number
if [ ! -e "$fiodir" ]; then
	echo "Usage $0 { block | file } <fio run number>"
	echo "Arguments are appended to identify path to fio data - $WORKSPACE/fio-results/arg1/arg2"
	if [ -e $WORKSPACE/fio-results/$iotype ]; then
		echo "Invalid arg2: <instance-number> in $WORKSPACE/fio-results/$iotype/<fio run number>"
	else
		echo "Invalid arg1: { block | file } in $WORKSPACE/fio-results/$iotype"
	fi
	exit 1
fi

# Aggregate fio test results in a single file to simplify report generation.  Each fio pod produces
# a tar file of fio results.  There is one fio result file per fio test.

pushd $fiodir >/dev/null 2>&1
tars=$(find | grep tar)
if [ -n "$tars" ]; then
	> fio-data-all.out
	pods=$(find -type d -name "fio*")
	for i in $pods
	do
		pushd $i >/dev/null 2>&1
		tars=( $(ls fio-results*.tar) )
		if [ -n "${tars[@]}" ]; then
			#  Only expecting one tar file
			tar -xvf "${tars[0]}" >/dev/null 2>&1
			for j in $(ls *.out)
			do
				echo "Fio $j results for pod ${i/\.\//} from ${tars[0]}" >> $fiodir/fio-data-all.out
				grep IOPS $j >> $fiodir/fio-data-all.out
			done
		else
			echo "Missing pod $i tar file"
			exit 1
		fi
		popd >/dev/null 2>&1
	done
else
	echo "There are no fio tar files"
	exit 1
fi
popd >/dev/null 2>&1

file=$fiodir/fio-data-all.out

echo -e "Fio data file: $file\n"

./helper/fio-extract-data.sh $file read 4k
./helper/fio-extract-data.sh $file read 16k
./helper/fio-extract-data.sh $file read 64k
./helper/fio-extract-data.sh $file read 128k
./helper/fio-extract-data.sh $file read 1024k

./helper/fio-extract-data.sh $file write 4k
./helper/fio-extract-data.sh $file write 16k
./helper/fio-extract-data.sh $file write 64k
./helper/fio-extract-data.sh $file write 128k
./helper/fio-extract-data.sh $file write 1024k

./helper/fio-extract-data.sh $file randrw 4k
./helper/fio-extract-data.sh $file randrw 16k
./helper/fio-extract-data.sh $file randrw 64k
./helper/fio-extract-data.sh $file randrw 128k
./helper/fio-extract-data.sh $file randrw 1024k

exit
