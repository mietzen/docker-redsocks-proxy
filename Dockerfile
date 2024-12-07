FROM golang:1-bookworm AS dnscrypt
ARG DNSCRYPT_VERSION=2.1.5

RUN mkdir /build
ADD https://github.com/DNSCrypt/dnscrypt-proxy/archive/refs/tags/${DNSCRYPT_VERSION}.tar.gz ./dnscrypt-proxy.tar.gz
RUN tar --strip-components=1 -xf dnscrypt-proxy.tar.gz -C /build
WORKDIR /build/dnscrypt-proxy
RUN go clean && CGO_ENABLED=0 go build -mod vendor -ldflags="-s -w"

FROM gcc:bookworm AS redsocks2
ARG REDSOCKS2_VERSION=release-0.71

RUN mkdir /build
RUN apt-get update && apt-get install -y \
        build-essential \
        libevent-dev \
        libssl-dev \
        zlib1g-dev
ADD https://github.com/semigodking/redsocks/archive/refs/tags/${REDSOCKS2_VERSION}.tar.gz ./redsocks2.tar.gz
RUN tar --strip-components=1 -xf redsocks2.tar.gz -C /build
WORKDIR /build
RUN make ENABLE_HTTPS_PROXY=true DISABLE_SHADOWSOCKS=true ENABLE_STATIC=true

FROM debian:bookworm-20241202
RUN apt-get update && apt-get install -y \
        iptables \
        curl \
        jq \
        sipcalc \
        dnsutils \
        procps \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*
COPY --from=dnscrypt /build/dnscrypt-proxy/dnscrypt-proxy /usr/sbin/dnscrypt-proxy
COPY --from=redsocks2 /build/redsocks2 /usr/sbin/redsocks2
COPY dnscrypt-proxy.toml.template /etc/dnscrypt-proxy.toml.template
COPY redsocks.conf.template /etc/redsocks.conf.template

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT /bin/bash /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
HEALTHCHECK --interval=10s --timeout=30s --start-period=5s --retries=3 \
        CMD /bin/bash /healthcheck.sh
