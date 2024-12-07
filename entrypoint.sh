#!/bin/bash

set -eo pipefail

# Variables
# DNSCrypt
export DNSCrypt_Active=${DNSCrypt_Active:-'true'}
DOH_SERVERS=${DOH_SERVERS:-"mullvad-doh, cloudflare"}
export FALL_BACK_DNS="'${FALL_BACK_DNS:-9.9.9.9}:53'"
# FIREWALL
ALLOW_DOCKER_CIDR=${ALLOW_DOCKER_CIDR:-true}
REDIRECT_PORTS=${REDIRECT_PORTS:-'all'}
# REDSOCKS
export LOG_DEBUG=${LOG_DEBUG:-off}
export LOG_INFO=${LOG_INFO:-on}
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
    if [[ $DNSCrypt_Active == true ]]; then
        echo "DNSCrypt:"
        echo "  - Generating DNSCrypt configuration"
        echo "  - Servers: $DOH_SERVERS"

        RESOLVERS_JSON=$(curl -s https://download.dnscrypt.info/dnscrypt-resolvers/json/public-resolvers.json)
        DOH_SERVERS=$(echo "$DOH_SERVERS" | sed 's/[[:space:]]//g')
        STATIC_BUFFER=""
        IFS=',' read -ra SERVERS <<< "$DOH_SERVERS"
        echo "  - Querying dns static stamps:"
        for SERVER in "${SERVERS[@]}"; do
            SERVER=$(echo "$SERVER" | xargs) # Trim spaces
            STAMP=$(echo "$RESOLVERS_JSON" | jq -r ".[] | select(.name == \"$SERVER\") | .stamp")
            if [[ -n "$STAMP" ]]; then
                echo "    - Found stamp for server $SERVER"
                STATIC_BUFFER+="  [static.'$SERVER']\n"
                STATIC_BUFFER+="  stamp = '$STAMP'\n"
            else
                echo "    - Warning: Stamp not found for server $SERVER"
            fi
        done
        if [[ -n "$STATIC_BUFFER" ]]; then
            echo "[static]" >> /opt/dnscrypt-proxy/dnscrypt-proxy.toml.template
            echo -e "$STATIC_BUFFER" >> /opt/dnscrypt-proxy/dnscrypt-proxy.toml.template
        else
            echo "    - No valid stamps found; skipping [static] block."
        fi

        export DOH_SERVERS=$(echo "$DOH_SERVERS" | sed "s/\([^,]*\)/'\1'/g" | sed 's/,/, /g')

        envsubst < /opt/dnscrypt-proxy/dnscrypt-proxy.toml.template > /opt/dnscrypt-proxy/dnscrypt-proxy.toml
        echo "  - DNSCrypt configuration:"
        sed 's/^/      /' /opt/dnscrypt-proxy/dnscrypt-proxy.toml
        touch /opt/dnscrypt-proxy/dnscrypt-proxy.log
        echo "  - Starting DNSCrypt"
        /opt/dnscrypt-proxy/dnscrypt-proxy -loglevel 2 -pidfile /opt/dnscrypt-proxy/dnscrypt.pid -config /opt/dnscrypt-proxy/dnscrypt-proxy.toml &> /opt/dnscrypt-proxy/dnscrypt-proxy.log &
    fi
}

configure_iptables() {
    echo "Firewall:"
    echo "  - Generating firewall rules"
    iptables -t nat -N REDSOCKS
    if [[ ! $PROXY_SERVER =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PROXY_IP=$(dig +short ${PROXY_SERVER} | head -n1)
    else
        PROXY_IP=$PROXY_SERVER
    fi
    echo "  - Whitelisting proxy server"
    echo "    - Proxy IP: $PROXY_IP"

    iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -p tcp -d ${PROXY_IP} --dport ${PROXY_PORT} -j RETURN

    if [[ $ALLOW_DOCKER_CIDR == true ]]; then
        echo "  - Whitelisting docker network"
        DOCKER_CIDR=$(sipcalc eth0 | grep -E 'Network address|Network mask \(bits\)' | awk -F'- ' '{print $2}' | paste -sd '/' -)
        echo "    - Docker CIDR: $DOCKER_CIDR"
        iptables -t nat -A REDSOCKS -d ${DOCKER_CIDR} -j RETURN
    fi

    if [[ $REDIRECT_PORTS == "all" ]]; then
        echo "  - Redirecting all TCP traffic"
        iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-port "$LOCAL_PORT"
    else
        REDIRECT_PORTS=$(echo "$REDIRECT_PORTS" | sed 's/[[:space:]]//g')
        IFS=',' read -ra PORTS <<< "$REDIRECT_PORTS"
        echo "  - Redirecting TCP Ports:"
        for PORT in "${PORTS[@]}"; do
            if is_valid_port "$PORT"; then
                echo "    - $PORT"
                iptables -t nat -A REDSOCKS -p tcp --dport "$PORT" -j REDIRECT --to-port "$LOCAL_PORT"
            else
                echo ""
                echo "Error: Invalid port: $PORT"
                exit 1
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
    echo "Redsocks:"
    if [ -z "$PROXY_SERVER" ] || [ -z "$PROXY_PORT" ]; then
        echo ""
        echo "Error: PROXY_SERVER and PROXY_PORT must be set."
        exit 1
    fi
    echo "  - Generating Redsocks configuration"
    envsubst < /opt/redsocks/redsocks.conf.template > /opt/redsocks/redsocks.conf
    # Remove both login and password if either is unset
    if [ -z "$LOGIN" ] || [ -z "$PASSWORD" ]; then
        sed -i '/login = /d' /opt/redsocks/redsocks.conf
        sed -i '/password = /d' /opt/redsocks/redsocks.conf
    fi
    echo "  - Redsocks configuration (sensitive data redacted):"
    sed -e 's/\(login = \).*/\1***;/' -e 's/\(password = \).*/\1***;/' /opt/redsocks/redsocks.conf | sed 's/^/      /'
    echo ""
    echo "  - Starting redsocks"
    /opt/redsocks/redsocks -c /opt/redsocks/redsocks.conf -p /opt/redsocks/redsocks.pid &> /opt/redsocks/redsocks.log &
    echo ""
}

echo "============= Initial Setup ============="
echo ""
setup_dnscrypt
setup_redsocks
configure_iptables
echo "================== Log =================="
echo ""
exec 3</opt/redsocks/redsocks.log
if [[ $DNSCrypt_Active == true ]]; then
    exec 4</opt/dnscrypt-proxy/dnscrypt-proxy.log
fi
while true; do
    if read -r line <&3; then
        timestamp=$(echo "$line" | awk '{print $1}')
        log_level=$(echo "$line" | awk '{print $2}' | tr 'a-z' 'A-Z')
        formatted_date=$(date -d @$timestamp '+[%Y-%m-%d %H:%M:%S]')
        padded_log_level="[$log_level]"
        padded_log_level=$(printf "%-8s" "$padded_log_level")  # Pad to ensure total width of 9 characters (6 chars + 3 spaces)
        echo "[Redsocks] $formatted_date $padded_log_level ${line#* * }"
    fi
    if [[ $DNSCrypt_Active == true ]]; then
        if read -r line <&4; then
            echo "[DNSCrypt] $line"
        fi
    fi
    sleep 0.5
done
