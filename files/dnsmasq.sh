#!/bin/bash

ARGS="$@"

if [[ "$ARGS" =~ "test-ocp" ]] && [[ ! "$ARGS" =~ "dns-forward-max" ]]; then
        exec /usr/sbin/dnsmasq.bin --dns-forward-max=1000 $ARGS
else
        exec /usr/sbin/dnsmasq.bin $ARGS
fi

