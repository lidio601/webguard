#!/bin/bash
echo "$(date) - Rimozione ban per $1"
iptables -D INPUT -p tcp -s "$1" --dport 80 -j REJECT
