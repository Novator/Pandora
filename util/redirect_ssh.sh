#!/bin/sh -e

while true; do
  echo "SSH port forward..."
  #killall ssh
  #--When 'GatewayPorts no' in /etc/ssh/sshd_config (default) and you have a redirector from external to local:
  #sshpass -p 'Password123' ssh user@mysshhost -4 -N -g -M -R 127.0.0.1:5577:127.0.0.1:5577 -o ExitOnForwardFailure=yes -o ServerAliveInterval=45 -o TCPKeepAlive=yes -o Protocol=2
  #--When 'GatewayPorts yes' in /etc/ssh/sshd_config, it works without redirector:
  sshpass -p 'Password123' ssh user@mysshhost -4 -N -g -M -R 222.222.222.222:5577:127.0.0.1:5577 -o ExitOnForwardFailure=yes -o ServerAliveInterval=45 -o TCPKeepAlive=yes -o Protocol=2
  sleep 2
done

