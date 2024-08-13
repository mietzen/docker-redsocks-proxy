FROM debian:stable-20240812

RUN apt-get update && apt-get install -y \
        iptables \
        redsocks \
        curl \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
COPY redsocks.conf.template /etc/redsocks.conf.template
ENTRYPOINT /bin/bash /entrypoint.sh