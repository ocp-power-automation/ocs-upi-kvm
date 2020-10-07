#!/bin/bash

ARGS="$@"

if [[ "$ARGS" =~ "libvirt" ]] && [[ ! "$ARGS" =~ "dns-forward-max" ]]; then
        echo "/usr/sbin/dnsmasq.bin --dns-forward-max=600 $ARGS" >> /tmp/dnsmasq.log
        /usr/sbin/dnsmasq.bin --dns-forward-max=600 $ARGS
else
        echo "/usr/sbin/dnsmasq.bin $ARGS" >> /tmp/dnsmasq.log
        /usr/sbin/dnsmasq.bin $ARGS
fi

