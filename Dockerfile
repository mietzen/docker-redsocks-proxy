FROM golang:1-trixie AS dnscrypt

RUN apt-get update && apt-get install -y curl jq
RUN DNSCRYPT_VERSION=$(curl -s https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest | jq -r .tag_name) \
    && echo "Building dnscrypt-proxy version: $DNSCRYPT_VERSION" \
    && mkdir /build \
    && curl -L "https://github.com/DNSCrypt/dnscrypt-proxy/archive/refs/tags/${DNSCRYPT_VERSION}.tar.gz" -o /dnscrypt-proxy.tar.gz \
    && tar --strip-components=1 -xf /dnscrypt-proxy.tar.gz -C /build

WORKDIR /build/dnscrypt-proxy
RUN go clean && CGO_ENABLED=0 go build -mod vendor -ldflags="-s -w"

FROM gcc:trixie AS redsocks
ARG REDSOCKS_VERSION=release-0.5

RUN mkdir /build
ADD https://github.com/darkk/redsocks/archive/refs/tags/${REDSOCKS_VERSION}.tar.gz ./redsocks.tar.gz
RUN tar --strip-components=1 -xf redsocks.tar.gz -C /build
WORKDIR /build
ADD https://patch-diff.githubusercontent.com/raw/darkk/redsocks/pull/123.patch libevent-2.1-compat.patch
RUN git apply libevent-2.1-compat.patch
RUN make

FROM debian:trixie-20251229
RUN apt-get update && apt-get install -y \
        adduser \
        curl \
        dnsutils \
        gettext-base \
        iptables \
        jq \
        libevent-core-2.1-7t64 \
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
