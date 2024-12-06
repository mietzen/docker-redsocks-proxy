#!/bin/bash

set -eo pipefail

DNSCrypt_Active=${DNSCrypt_Active:-'true'}

if [[ $DNSCrypt_Active == true ]]; then
    RESOLVERS_JSON=$(curl -s https://download.dnscrypt.info/dnscrypt-resolvers/json/public-resolvers.json)
    # Set DNS values
    DOH_SERVERS=${DOH_SERVERS:-"quad9-doh-ip4-port443-nofilter-ecs-pri, quad9-doh-ip4-port443-nofilter-pri"}
    DOH_SERVERS=$(echo "$DOH_SERVERS" | sed 's/[[:space:]]//g')
    export FALL_BACK_DNS="'${FALL_BACK_DNS:-9.9.9.9}:53'"

    # Initialize a buffer for the [static] block
    STATIC_BUFFER=""

    # Process each server
    IFS=',' read -ra SERVERS <<< "$DOH_SERVERS"
    for SERVER in "${SERVERS[@]}"; do
        SERVER=$(echo "$SERVER" | xargs) # Trim spaces
        STAMP=$(echo "$RESOLVERS_JSON" | jq -r ".[] | select(.name == \"$SERVER\") | .stamp")

        if [[ -n "$STAMP" ]]; then
            # Add the TOML entry to the buffer
            STATIC_BUFFER+="  [static.'$SERVER']\n"
            STATIC_BUFFER+="  stamp = '$STAMP'\n"
        else
            echo "Warning: Stamp not found for server $SERVER" >&2
        fi
    done

    # Append the [static] block to the configuration file only if it contains entries
    if [[ -n "$STATIC_BUFFER" ]]; then
        echo "[static]" >> /etc/dnscrypt-proxy.toml.template
        echo -e "$STATIC_BUFFER" >> /etc/dnscrypt-proxy.toml.template
    else
        echo "No valid stamps found; skipping [static] block."
    fi

    export DOH_SERVERS=$(echo "$DOH_SERVERS" | sed "s/\([^,]*\)/'\1'/g" | sed 's/,/, /g')

    # Generate DNSCrypt configuration file
    echo "Generating DNSCrypt configuration..."
    envsubst < /etc/dnscrypt-proxy.toml.template > /etc/dnscrypt-proxy.toml

    echo "Final DNSCrypt configuration:"
    cat /etc/dnscrypt-proxy.toml
    echo ""
    dnscrypt-proxy -syslog -config /etc/dnscrypt-proxy.toml &
fi

set -x

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

# Generate Redsocks configuration file
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

# Create the REDSOCKS chain for TCP traffic
iptables -t nat -N REDSOCKS

if [[ ! $PROXY_SERVER =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    PROXY_IP=$(dig +short ${PROXY_SERVER} | head -n1)
else
    PROXY_IP=$PROXY_SERVER
fi

echo "Proxy IP: $PROXY_IP"

iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -p tcp -d ${PROXY_IP} --dport ${PROXY_PORT} -j RETURN

ALLOW_DOCKER_CIDR=${ALLOW_DOCKER_CIDR:-true}

# Apply ALLOW_DOCKER_CIDR logic
if [[ $ALLOW_DOCKER_CIDR == true ]]; then
    network_info=$(sipcalc eth0 | grep -E 'Network address|Network mask \(bits\)' | awk -F'- ' '{print $2}')
    network_address=$(echo "$network_info" | head -n 1)
    subnet_bits=$(echo "$network_info" | tail -n 1)
    DOCKER_CIDR="$network_address/$subnet_bits"

    echo "Local CIDR: $DOCKER_CIDR"
    iptables -t nat -A REDSOCKS -d ${DOCKER_CIDR} -j RETURN
fi

REDIRECT_PORTS=${REDIRECT_PORTS:-'all'}

# Function to check if a port is valid
is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

if [[ $REDIRECT_PORTS == "all" ]]; then
    # Redirect all other TCP traffic to port "$LOCAL_PORT"
    iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-port "$LOCAL_PORT"
else
    # Use xargs to handle spaces and split ports
    echo "$REDIRECT_PORTS" | xargs -n 1 | while read port; do
        # Check if the port is a valid integer in the valid IPv4 port range
        if is_valid_port "$port"; then
            iptables -t nat -A REDSOCKS -p tcp --dport "$port" -j REDIRECT --to-port "$LOCAL_PORT"
        else
            echo "Invalid port: $port (skipping)"
        fi
    done
fi

# Apply the REDSOCKS chain to OUTPUT
iptables -t nat -A OUTPUT -p tcp -j REDSOCKS

if [[ $DNSCrypt_Active == true ]]; then
    # Redirect all UDP port 53 traffic to port 5533
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port 5533
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port 5533
fi

echo "Container IP Address: $(curl -sSL https://v4.ident.me)"
tail -f /var/log/redsocks.log
