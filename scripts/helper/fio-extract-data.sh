#!/bin/bash

file=$1
if [ ! -e "$file" ]; then
        echo "Missing file"
        echo "Invalid arg: test=${test} Expecting read, write, or randrw"
        exit 1
fi

test=$2                 # read, write, randrw
case "$test" in
        read|write|randrw)
                ;;
        *)
                echo "$0 <file> <test> <bs>"
                echo "Invalid arg: test=${test} Expecting read, write, or randrw"
                exit 1;
                ;;
esac

bs=$3                   # 4k, 64k, 128k
case "$bs" in
        4k|16k|64k|128k|1024k)
                ;;
        *)
                echo "$0 <file> <test> <bs>"
                echo "Invalid arg: bs=${bs} Expecting 4k, 64k, or 128k"
                exit 1;
                ;;
esac

function calc_bw () {
        lbw=( $@ )

        for i in "${lbw[@]}"
        do
                if [[ "$i" =~ K ]]; then
                        KiBs=${i/K/}
                elif [[ "$i" =~ B ]]; then
                        Bytes=${i/B/}
                        KiBs=$(awk -v j=$Bytes 'BEGIN {x=j; y=x/1024; print y}')
                else
                        MBytes=${i/M/}
                        KiBs=$(awk -v j=$MBytes 'BEGIN {x=j; y=x*1024; print y}')
                fi

                #echo --- totalBW=$totalBW i=$i KiBs=$KiBs

                totalBW=$(awk -v t=$totalBW -v k=$KiBs 'BEGIN {x=t; y=k; z=x+y; print z}')
        done
}

function calc_iops () {
        liops=( $@ )

        for i in "${liops[@]}"
        do
                (( totalIOPs = totalIOPs + $i ))
        done
}

#echo "Accumulating results for $test-$bs from $file"

case "$test" in
        read|write)
                lines=$(awk "/$test-$bs/{print;getline;print}" $file )
                bw=( $(echo "$lines" | grep IOPS | awk '{print $3}' | sed 's/BW=//' | sed 's/KiB\/s/K/' | sed 's/MiB\/s/M/' | sed 's/B\/s/B/' ) )
                iops=( $(echo "$lines" | grep IOPS | awk '{print $2}' | sed 's/IOPS=//' | sed 's/,//' ) )

                #echo "Number of samples=${#bw[@]}"
                #echo "Samples=${bw[@]}"

                totalBW=0
                calc_bw "${bw[@]}"
                echo Total $test $bs BW is "$totalBW KiB/s"

                totalIOPs=0
                calc_iops "${iops[@]}"
                echo Total $test $bs IOPs is "$totalIOPs"

		echo "---"

                exit
                ;;
        randrw)
                lines=$(awk "/$test-$bs/{print;getline;print;getline;print}" $file )

                readBW=( $(echo "$lines" | grep "read: IOPS" | awk '{print $3}' | sed 's/BW=//' | sed 's/KiB\/s/K/' | sed 's/MiB\/s/M/' | sed 's/B\/s/B/' ) )
                readIOPs=( $(echo "$lines" | grep "read: IOPS" | awk '{print $2}' | sed 's/IOPS=//' | sed 's/,//' ) )

                #echo "Number of $test read samples=${#readBW[@]}"
                #echo "Read samples=${readBW[@]}"

                totalBW=0
                calc_bw "${readBW[@]}"
                echo Total $test $bs read BW is "$totalBW KiB/s"
                totalReadBW=$totalBW

                totalIOPs=0
                calc_iops "${readIOPs[@]}"
                echo Total $test $bs read IOPs is "$totalIOPs"
                totalReadIOPs=$totalIOPs

                writeBW=( $(echo "$lines" | grep "write: IOPS" | awk '{print $3}' | sed 's/BW=//' | sed 's/KiB\/s/K/' | sed 's/MiB\/s/M/' | sed 's/B\/s/B/' ) )
                writeIOPs=( $(echo "$lines" | grep "write: IOPS" | awk '{print $2}' | sed 's/IOPS=//' | sed 's/,//' ) )

                #echo "Number of $test write samples=${#writeBW[@]}"
                #echo "Write samples=${writeBW[@]}"

                totalBW=0
                calc_bw "${writeBW[@]}"
                echo Total $test $bs write BW is "$totalBW KiB/s"
                totalWriteBW=$totalBW

                totalIOPs=0
                calc_iops "${writeIOPs[@]}"
                echo Total $test $bs write IOPs is "$totalIOPs"
                totalWriteIOPs=$totalIOPs

		totalBW=$(awk -v a=$totalReadBW -v b=$totalWriteBW 'BEGIN {x=a; y=b; z=x+y; print z}')

                echo "Total $test $bs read+write BW is $totalBW KiB/s"
                echo "Total $test $bs read+write IOPs is $(( totalReadIOPs + totalWriteIOPs ))"

		echo "---"

                exit
                ;;
esac
