#!/bin/bash

set -e

# Set default values for optional variables
export LOG_DEBUG=${LOG_DEBUG:-off}
export LOG_INFO=${LOG_INFO:-on}
export LOG_FILE="${LOG_FILE:-/var/log/redsocks.log}"
export LOG="\"file:${LOG_FILE}\""
export LOCAL_IP=${LOCAL_IP:-127.0.0.1}
export LOCAL_PORT=${LOCAL_PORT:-8081}
export PROXY_TYPE=${PROXY_TYPE:-socks5}
export TCP_KEEPALIVE_TIME=${TCP_KEEPALIVE_TIME:-0}
export TCP_KEEPALIVE_PROBES=${TCP_KEEPALIVE_PROBES:-0}
export TCP_KEEPALIVE_INTVL=${TCP_KEEPALIVE_INTVL:-0}
export RLIMIT_NOFILE=${RLIMIT_NOFILE:-0}
export REDSOCKS_CONN_MAX=${REDSOCKS_CONN_MAX:-0}
export CONNPRES_IDLE_TIMEOUT=${CONNPRES_IDLE_TIMEOUT:-7440}  # Default is 2 hours 4 minutes (RFC 5382)
export MAX_ACCEPT_BACKOFF=${MAX_ACCEPT_BACKOFF:-60000}
export ON_PROXY_FAIL=${ON_PROXY_FAIL:-close}
export DISCLOSE_SRC=${DISCLOSE_SRC:-false}
export LISTENQ=${LISTENQ:-128}
export SPLICE=${SPLICE:-false}

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

# Print final configuration for debugging
echo "Final Redsocks configuration (sensitive data redacted):"
sed -e 's/\(login = \).*/\1***;/' -e 's/\(password = \).*/\1***;/' /etc/redsocks.conf

# Restart Redsocks service and configure iptables
echo "Restarting Redsocks and configuring iptables..."
/etc/init.d/redsocks restart

iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port "$LOCAL_PORT"
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port "$LOCAL_PORT"

echo "Container IP Address: $(curl -sSL https://v4.ident.me)"
tail -f "$LOG_FILE"
