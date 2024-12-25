FROM golang:1-bookworm AS dnscrypt
ARG DNSCRYPT_VERSION=2.1.5

RUN mkdir /build
ADD https://github.com/DNSCrypt/dnscrypt-proxy/archive/refs/tags/${DNSCRYPT_VERSION}.tar.gz ./dnscrypt-proxy.tar.gz
RUN tar --strip-components=1 -xf dnscrypt-proxy.tar.gz -C /build
WORKDIR /build/dnscrypt-proxy
RUN go clean && CGO_ENABLED=0 go build -mod vendor -ldflags="-s -w"

FROM gcc:bookworm AS redsocks
ARG REDSOCKS_VERSION=release-0.5

RUN mkdir /build
ADD https://github.com/darkk/redsocks/archive/refs/tags/${REDSOCKS_VERSION}.tar.gz ./redsocks.tar.gz
RUN tar --strip-components=1 -xf redsocks.tar.gz -C /build
WORKDIR /build
ADD https://patch-diff.githubusercontent.com/raw/darkk/redsocks/pull/123.patch libevent-2.1-compat.patch
RUN git apply libevent-2.1-compat.patch
RUN make

FROM debian:bookworm-20241223
RUN apt-get update && apt-get install -y \
        curl \
        dnsutils \
        gettext-base \
        iptables \
        jq \
        libevent-core-2.1-7 \
        procps \
        sipcalc \
    && rm -rf /var/lib/apt/lists/*
RUN adduser --system --shell /bin/bash --home /opt/redsocks --group --disabled-login redsocks && \
    adduser --system --shell /bin/bash --home /opt/dnscrypt --group --disabled-login dnscrypt

COPY --from=dnscrypt /build/dnscrypt-proxy/dnscrypt-proxy /opt/dnscrypt/dnscrypt-proxy
COPY dnscrypt-config.toml.template /opt/dnscrypt/dnscrypt-config.toml.template
COPY --from=redsocks /build/redsocks /opt/redsocks/redsocks
COPY redsocks.conf.template /opt/redsocks/redsocks.conf.template

RUN chown -R dnscrypt:dnscrypt /opt/dnscrypt && \
    chown -R redsocks:redsocks /opt/redsocks

COPY entrypoint.sh /entrypoint.sh
SHELL [ "/bin/bash" ]
ENTRYPOINT [ "/entrypoint.sh" ]

COPY healthcheck.sh /healthcheck.sh
HEALTHCHECK --interval=10s --timeout=30s --start-period=5s --retries=3 \
        CMD /bin/bash /healthcheck.sh
