FROM debian:stable-20241202

COPY pinning.pref /etc/apt/preferences.d/pinning.pref
RUN apt-get update && apt-get install -y \
        iptables \
        redsocks \
        curl \
        tcpdump \
        gettext-base
RUN echo "deb https://deb.debian.org/debian/ testing main" | tee /etc/apt/sources.list.d/testing.list \
    && apt-get update && apt-get install -t testing -y \
        dnscrypt-proxy \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
COPY dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
COPY redsocks.conf.template /etc/redsocks.conf.template
ENTRYPOINT /bin/bash /entrypoint.sh
