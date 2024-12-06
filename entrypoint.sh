#!/bin/bash

set -eo pipefail

# Variables
# DNSCrypt
DNSCrypt_Active=${DNSCrypt_Active:-'true'}
DOH_SERVERS=${DOH_SERVERS:-"quad9-doh-ip4-port443-nofilter-ecs-pri, quad9-doh-ip4-port443-nofilter-pri"}
export FALL_BACK_DNS="'${FALL_BACK_DNS:-9.9.9.9}:53'"
# FIREWALL
ALLOW_DOCKER_CIDR=${ALLOW_DOCKER_CIDR:-true}
REDIRECT_PORTS=${REDIRECT_PORTS:-'all'}
# REDSOCKS
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

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

setup_dnscrypt() {
    echo "---- DNSCRYPT -----"
    if [[ $DNSCrypt_Active == true ]]; then
        echo "Generating DNSCrypt configuration"
        echo "Servers: $DOH_SERVERS"

        RESOLVERS_JSON=$(curl -s https://download.dnscrypt.info/dnscrypt-resolvers/json/public-resolvers.json)
        DOH_SERVERS=$(echo "$DOH_SERVERS" | sed 's/[[:space:]]//g')
        STATIC_BUFFER=""
        IFS=',' read -ra SERVERS <<< "$DOH_SERVERS"
        echo "Querying dns static stamps:"
        for SERVER in "${SERVERS[@]}"; do
            SERVER=$(echo "$SERVER" | xargs) # Trim spaces
            STAMP=$(echo "$RESOLVERS_JSON" | jq -r ".[] | select(.name == \"$SERVER\") | .stamp")
            if [[ -n "$STAMP" ]]; then
                echo "  Found stamp for server $SERVER"
                STATIC_BUFFER+="  [static.'$SERVER']\n"
                STATIC_BUFFER+="  stamp = '$STAMP'\n"
            else
                echo "  Warning: Stamp not found for server $SERVER" >&2
            fi
        done
        if [[ -n "$STATIC_BUFFER" ]]; then
            echo "[static]" >> /etc/dnscrypt-proxy.toml.template
            echo -e "$STATIC_BUFFER" >> /etc/dnscrypt-proxy.toml.template
        else
            echo "  No valid stamps found; skipping [static] block."
        fi

        export DOH_SERVERS=$(echo "$DOH_SERVERS" | sed "s/\([^,]*\)/'\1'/g" | sed 's/,/, /g')

        envsubst < /etc/dnscrypt-proxy.toml.template > /etc/dnscrypt-proxy.toml
        echo "DNSCrypt configuration:"
        cat /etc/dnscrypt-proxy.toml | sed 's/^/    /'
        echo ""
        touch /var/log/dnscrypt-proxy.log
        dnscrypt-proxy -loglevel 2 -logfile /var/log/dnscrypt-proxy.log -config /etc/dnscrypt-proxy.toml &
    fi
}

configure_iptables() {
    echo "---- FIREWALL -----"
    echo "Generating firewall rules"
    iptables -t nat -N REDSOCKS
    if [[ ! $PROXY_SERVER =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PROXY_IP=$(dig +short ${PROXY_SERVER} | head -n1)
    else
        PROXY_IP=$PROXY_SERVER
    fi
    echo "Whitelisting proxy server"
    echo "  Proxy IP: $PROXY_IP"

    iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -p tcp -d ${PROXY_IP} --dport ${PROXY_PORT} -j RETURN

    if [[ $ALLOW_DOCKER_CIDR == true ]]; then
        echo "Whitelisting docker network"
        network_info=$(sipcalc eth0 | grep -E 'Network address|Network mask \(bits\)' | awk -F'- ' '{print $2}')
        network_address=$(echo "$network_info" | head -n 1)
        subnet_bits=$(echo "$network_info" | tail -n 1)
        DOCKER_CIDR="$network_address/$subnet_bits"

        echo "  Docker CIDR: $DOCKER_CIDR"
        iptables -t nat -A REDSOCKS -d ${DOCKER_CIDR} -j RETURN
    fi

    if [[ $REDIRECT_PORTS == "all" ]]; then
        echo "Redirecting all TCP traffic"
        iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-port "$LOCAL_PORT"
    else
        echo "$REDIRECT_PORTS" | xargs -n 1 | while read port; do
            if is_valid_port "$port"; then
                echo "Redirecting port: $port"
                iptables -t nat -A REDSOCKS -p tcp --dport "$port" -j REDIRECT --to-port "$LOCAL_PORT"
            else
                echo "Invalid port: $port (skipping)"
            fi
        done
    fi

    iptables -t nat -A OUTPUT -p tcp -j REDSOCKS

    if [[ $DNSCrypt_Active == true ]]; then
        iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port 5533
        iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port 5533
    fi
    echo ""
}

setup_redsocks() {
    echo "---- REDSOCKS -----"
    if [ -z "$PROXY_SERVER" ] || [ -z "$PROXY_PORT" ]; then
        echo "Error: PROXY_SERVER and PROXY_PORT must be set."
        exit 1
    fi
    echo "Generating Redsocks configuration"
    envsubst < /etc/redsocks.conf.template > /etc/redsocks.conf
    # Remove both login and password if either is unset
    if [ -z "$LOGIN" ] || [ -z "$PASSWORD" ]; then
        sed -i '/login = /d' /etc/redsocks.conf
        sed -i '/password = /d' /etc/redsocks.conf
    fi
    echo "Redsocks configuration (sensitive data redacted):"
    sed -e 's/\(login = \).*/\1***;/' -e 's/\(password = \).*/\1***;/' /etc/redsocks.conf | sed 's/^/    /'
    echo ""
    echo "Restarting redsocks"
    /etc/init.d/redsocks restart > /dev/null
    echo ""
}

echo "============= Initial Setup ============="
echo ""
setup_dnscrypt
setup_redsocks
configure_iptables
echo ""
echo "================== Log =================="
echo ""
exec 3</var/log/redsocks.log
exec 4</var/log/dnscrypt-proxy.log
while true; do
    if read -r line <&3; then
        timestamp=$(echo "$line" | awk '{print $1}')
        log_level=$(echo "$line" | awk '{print $2}' | tr 'a-z' 'A-Z')
        formatted_date=$(date -d @$timestamp '+[%Y-%m-%d %H:%M:%S]')
        padded_log_level="[$log_level]"
        padded_log_level=$(printf "%-8s" "$padded_log_level")  # Pad to ensure total width of 9 characters (6 chars + 3 spaces)
        echo "[Redsocks] $formatted_date $padded_log_level ${line#* * }"
    fi
    if read -r line <&4; then
        # Output the dnscrypt log line as is
        echo "[DNSCrypt] $line"
    fi
    sleep 0.1
done
