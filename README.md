# Docker Mullvad Redsocks Proxy

This is an example on how to use redsocks to proxy all http and https traffic through a mullvad socks5 proxy.

In this example the http and https traffic of the debian container will always be redirected through the set proxy. This perquisites that your docker host is already running inside the mullvad VPN.

compose-file:
```yaml
version: "3"

services:
  redsocks:
    image: mietzen/redsocks-proxy:stable
    hostname: redsocks
    privileged: true
    environment:
      - PROXY_SERVER=de-ber-wg-socks5-005.relays.mullvad.net
      - PROXY_PORT=1080
    dns: 9.9.9.9
    restart: unless-stopped

  debian:
    image: mietzen/debian-curl-jq:stable
    depends_on:
      - redsocks
    network_mode: service:redsocks
    command: /bin/bash -c "while true; do curl -sSL https://am.i.mullvad.net/connected && sleep 10; done"
    restart: unless-stopped
```

Output:

```shell
Attaching to debian-1, redsocks-1
redsocks-1  | Configuration:
redsocks-1  | PROXY_SERVER: de-ber-wg-socks5-005.relays.mullvad.net
redsocks-1  | PROXY_PORT: 1080
redsocks-1  | Setting config variables
redsocks-1  | Restarting redsocks and redirecting traffic via iptables
redsocks-1  | Restarting redsocks: redsocks.
redsocks-1  | Getting IP ...
redsocks-1  | You are connected to Mullvad (server de-ber-wg-socks5-005). Your IP address is 193.32.248.181
redsocks-1  | 1722762436.099561 notice main.c:165 main(...) redsocks started, conn_max=131072
redsocks-1  | 1722762436.183053 info redsocks.c:1243 redsocks_accept_client(...) [172.19.0.2:38986->45.83.223.233:443]: accepted
redsocks-1  | 1722762436.240962 info redsocks.c:1243 redsocks_accept_client(...) [172.19.0.2:39002->45.83.223.233:443]: accepted
debian-1    | You are connected to Mullvad (server de-ber-wg-socks5-005). Your IP address is 193.32.248.181
```


If your docker host is not already connected to the mullvad VPN you might want to use [gluetun](https://hub.docker.com/r/qmcgaw/gluetun) and stack the network connection, e.g.:

```yaml
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !!! NOT A WORKING EXAMPLE !!!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# You need to setup gluetun yourself!

version: "3"

services:
  gluetun:
    image: qmcgaw/gluetun
    hostname: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - ./gluetun:/gluetun
    environment:
      # See https://github.com/qdm12/gluetun-wiki/tree/main/setup#setup
      # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      # !!! HERE IS STILL SOME SETUP NEEDED!!!
      # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      # ...
    restart: unless-stopped
    dns: 9.9.9.9

  redsocks:
    image: mietzen/redsocks-proxy:stable
    hostname: redsocks
    depends_on:
      - gluetun
    privileged: true
    environment:
      - PROXY_SERVER=de-ber-wg-socks5-005.relays.mullvad.net
      - PROXY_PORT=1080
    network_mode: service:gluetun
    restart: unless-stopped

  debian:
    image: mietzen/debian-curl-jq:stable
    depends_on:
      - redsocks
    network_mode: service:redsocks
    command: /bin/bash -c "while true; do curl -sSL https://am.i.mullvad.net/connected && sleep 10; done"
    restart: unless-stopped
```
