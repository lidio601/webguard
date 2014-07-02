#!/bin/bash
echo "$(date) - Impostazione ban per $1"
iptables -A INPUT -p tcp -s "$1" --dport 80 -j REJECT
