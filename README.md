# Docker Redsocks Proxy

With this container, you can redirect all TCP traffic through a SOCKS5 proxy, with optional DNSCrypt integration for secure DNS resolution.

## Features:

- Route all TCP traffic or just specific ports through the proxy
- DNSCrypt for DoH (DNS over HTTPS) name resolution through the proxy (can be disabled)
- Easy configuration via environment variables

## Example Usage

In this example, the HTTP and HTTPS traffic of the `debian` container will always be redirected through the configured proxy. This requires that your Docker host is already connected to the VPN network (in this case, Mullvad VPN).

```yaml
services:
  redsocks:
    image: mietzen/redsocks-proxy:stable
    hostname: redsocks
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      - PROXY_SERVER=de-ber-wg-socks5-005.relays.mullvad.net
      - PROXY_PORT=1080
      # Optional:
      # DNSCrypt:
      - DNSCrypt_Active=true
      - DOH_SERVERS=quad9-doh-ip4-port443-nofilter-ecs-pri, quad9-doh-ip4-port443-nofilter-pri # Server-List: https://dnscrypt.info/public-servers/
      - FALL_BACK_DNS=9.9.9.9
      # FIREWALL:
      - REDIRECT_PORTS=all # Only certain port, e.g. REDIRECT_PORTS=21,80,443
      - ALLOW_DOCKER_CIDR=true # Allow networking between containers
      - LIMIT_UDP=true # Drop outgoing UDP traffic (DNS is whitelisted)
      # REDSOCKS:
      # - LOGIN=myuser
      # - PASSWORD=mypass
      - LOCAL_IP=127.0.0.1
      - LOCAL_PORT=8081
      - PROXY_TYPE=socks5
      - LOG_DEBUG=off
      - LOG_INFO=on
      - CONNPRES_IDLE_TIMEOUT=7440
      - DISCLOSE_SRC=false
      - LISTENQ=128
      - MAX_ACCEPT_BACKOFF=60000
      - ON_PROXY_FAIL=close
      - REDSOCKS_CONN_MAX=500
      - RLIMIT_NOFILE=1024
      - SPLICE=false
      - TCP_KEEPALIVE_INTVL=75
      - TCP_KEEPALIVE_PROBES=9
      - TCP_KEEPALIVE_TIME=300
    dns: 9.9.9.9 # Optional, but recommended if not using DNSCrypt
    # Optional: Uncomment the following and put down PROXY_SERVER=host.docker.internal if you wish to connect to a proxy on the host machine
    # extra_hosts:
    #     - host.docker.internal:host-gateway
    restart: unless-stopped

  debian:
    image: mietzen/debian-curl-jq:stable
    depends_on:
      redsocks:
        condition: service_healthy
    network_mode: service:redsocks
    command: /bin/bash -c 'while true; do echo "[Deb-cURL] $$(date '"'"'+[%Y-%m-%d %H:%M:%S]'"'"') [INFO]   $$(curl -sSL https://am.i.mullvad.net/connected)" && sleep 10; done'
    restart: unless-stopped
```

```shell
redsocks-1  | ================== Log ==================
redsocks-1  | 
redsocks-1  | [Redsocks] [2024-12-06 19:29:24] [NOTICE] main.c:165 main(...) redsocks started, conn_max=393216
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] dnscrypt-proxy 2.1.5
redsocks-1  | [Redsocks] [2024-12-06 19:29:24] [INFO]   redsocks.c:1243 redsocks_accept_client(...) [172.19.0.2:47174->149.112.112.12:443]: accepted
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] Network connectivity detected
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] Now listening to 127.0.0.1:5533 [UDP]
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] Now listening to 127.0.0.1:5533 [TCP]
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] Firefox workaround initialized
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] [quad9-doh-ip4-port443-nofilter-pri] OK (DoH) - rtt: 26ms
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] [quad9-doh-ip4-port443-nofilter-ecs-pri] OK (DoH) - rtt: 38ms
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] Sorted latencies:
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:24] [NOTICE] -    26ms quad9-doh-ip4-port443-nofilter-pri
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:25] [NOTICE] -    38ms quad9-doh-ip4-port443-nofilter-ecs-pri
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:25] [NOTICE] Server with the lowest initial latency: quad9-doh-ip4-port443-nofilter-pri (rtt: 26ms)
redsocks-1  | [DNSCrypt] [2024-12-06 19:29:25] [NOTICE] dnscrypt-proxy is ready - live servers: 2
redsocks-1  | [Redsocks] [2024-12-06 19:29:29] [INFO]   redsocks.c:1243 redsocks_accept_client(...) [172.19.0.2:57850->45.83.223.233:443]: accepted
debian-1    | [Deb-cURL] [2024-12-06 19:29:29] [INFO]   You are connected to Mullvad (server de-ber-wg-socks5-005). Your IP address is 193.32.248.181
redsocks-1  | [Redsocks] [2024-12-06 19:29:29] [INFO]   redsocks.c:671 redsocks_drop_client(...) [172.19.0.2:57850->45.83.223.233:443]: connection closed
```

### Published Ports

If your container behind `redsocks` exposes a port, that port is mirrored to the `redsocks` container. You can access it by opening the port on the `redsocks` container:

```yaml
services:
  redsocks:
    image: mietzen/redsocks-proxy:stable
    hostname: redsocks
    ports:
      - "8080:2001" # Port exposure on redsocks
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      - PROXY_SERVER=de-ber-wg-socks5-005.relays.mullvad.net
      - PROXY_PORT=1080
    dns: 9.9.9.9
    restart: unless-stopped
  whoami:
    image: traefik/whoami
    depends_on:
      redsocks:
        condition: service_healthy
    command:
       - --port=2001
    network_mode: service:redsocks
    restart: unless-stopped
```

```shell
$ curl http://localhost:8080/
Hostname: redsocks
IP: 127.0.0.1
IP: ::1
IP: 172.20.0.2
IP: fe80::42:acff:fe14:2
RemoteAddr: 172.16.0.1:59666
GET / HTTP/1.1
Host: localhost:8080
User-Agent: curl/8.9.1
Accept: */*
```

**Sources:**
- [PXke's blog: Using redsocks to proxy a docker container traffic](https://web.archive.org/web/20240302223218/https://blog.pxke.me/redsocksdocker.html)
- [SO Answer from marlar: How to make docker container connect everything through proxy](https://stackoverflow.com/a/71099635)
- [Docker Community Forums: Difficulty finding documentation about how network_mode: “service:<service_name>” works](https://web.archive.org/web/20240721062403/https://forums.docker.com/t/difficulty-finding-documentation-about-how-network-mode-service-service-name-works/137008)
