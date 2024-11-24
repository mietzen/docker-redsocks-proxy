#!/bin/bash

set -e

# Set default values for optional variables
: "${LOG_DEBUG:=off}"
: "${LOG_INFO:=on}"
: "${LOG:='file:/var/log/redsocks.log'}"
: "${LOCAL_IP:=127.0.0.1}"
: "${LOCAL_PORT:=8081}"
: "${PROXY_TYPE:=socks5}"
: "${TCP_KEEPALIVE_TIME:=0}"
: "${TCP_KEEPALIVE_PROBES:=0}"
: "${TCP_KEEPALIVE_INTVL:=0}"
: "${RLIMIT_NOFILE:=0}"
: "${REDSOCKS_CONN_MAX:=0}"
: "${CONNPRES_IDLE_TIMEOUT:=7440}"  # Default is 2 hours 4 minutes (RFC 5382)
: "${MAX_ACCEPT_BACKOFF:=60000}"
: "${ON_PROXY_FAIL:=close}"
: "${DISCLOSE_SRC:=false}"
: "${LISTENQ:=128}"
: "${SPLICE:=false}"

# Validate mandatory variables
if [ -z "$PROXY_SERVER" ] || [ -z "$PROXY_PORT" ]; then
    echo "Error: PROXY_SERVER and PROXY_PORT must be set."
    exit 1
fi

# Generate the configuration file
echo "Generating Redsocks configuration..."
envsubst < /etc/redsocks.conf.template > /etc/redsocks.conf

# Remove both login and password if either is unset
if [ -z "$LOGIN" ] || [ -z "$PASSWORD" ]; then
    sed -i '/login = /d' /etc/redsocks.conf
    sed -i '/password = /d' /etc/redsocks.conf
fi

# Print final configuration for debugging (optional)
echo "Final Redsocks configuration:"
cat /etc/redsocks.conf

# Restart Redsocks service and configure iptables
echo "Restarting Redsocks and configuring iptables..."
/etc/init.d/redsocks restart

iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port "$LOCAL_PORT"
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port "$LOCAL_PORT"

echo "Container IP Address: $(curl -sSL https://v4.ident.me)"
tail -f /var/log/redsocks.log
