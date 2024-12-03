FROM debian:stable-20241202

RUN apt-get update && apt-get install -y \
        iptables \
        redsocks \
        curl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
COPY redsocks.conf.template /etc/redsocks.conf.template
ENTRYPOINT /bin/bash /entrypoint.sh