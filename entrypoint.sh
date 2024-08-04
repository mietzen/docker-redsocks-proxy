#!/bin/bash
echo "Configuration:"
echo "PROXY_SERVER: $PROXY_SERVER"
echo "PROXY_PORT: $PROXY_PORT"
echo "Setting config variables"
sed "s/vPROXY-SERVER/$PROXY_SERVER/g" /etc/redsocks.conf.template > /etc/redsocks.conf
sed -i "s/vPROXY-PORT/$PROXY_PORT/g" /etc/redsocks.conf
echo "Restarting redsocks and redirecting traffic via iptables"
/etc/init.d/redsocks restart
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8081
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8081
echo "Getting IP ..."
curl -sSL https://am.i.mullvad.net/connected
tail -f /var/log/redsocks.log