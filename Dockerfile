FROM golang:1.23-bookworm AS dnscrypt
ARG DNSCRYPT_VERSION=2.1.5

RUN mkdir source
ADD https://github.com/DNSCrypt/dnscrypt-proxy/archive/refs/tags/${DNSCRYPT_VERSION}.tar.gz ./dnscrypt-proxy.tar.gz
RUN tar --strip-components=1 -xf dnscrypt-proxy.tar.gz -C /go/source
WORKDIR source/dnscrypt-proxy
RUN go clean && CGO_ENABLED=0 go build -mod vendor -ldflags="-s -w"

FROM debian:bookworm-20241202
RUN apt-get update && apt-get install -y \
        iptables \
        redsocks \
        curl \
        jq \
        sipcalc \
        dnsutils \
        procps \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*
COPY --from=dnscrypt /go/source/dnscrypt-proxy/dnscrypt-proxy /usr/sbin/dnscrypt-proxy
COPY dnscrypt-proxy.toml.template /etc/dnscrypt-proxy.toml.template
COPY redsocks.conf.template /etc/redsocks.conf.template

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT /bin/bash /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
HEALTHCHECK --interval=10s --timeout=30s --start-period=5s --retries=3 \
        CMD /bin/bash /healthcheck.sh
