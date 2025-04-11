#!/bin/bash

# Check if LAN gateway is reachable
if ping -c 1 192.168.9.1 &>/dev/null; then
    cp /etc/coredns/Corefile.lan /etc/coredns/Corefile
else
    cp /etc/coredns/Corefile.wifi /etc/coredns/Corefile
fi
systemctl restart coredns