FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      telnet \
      netcat-openbsd \
      nmap \
      mailutils \
      iproute2 \
      iputils-ping \
      iputils-arping \
      dnsutils \
      net-tools \
      procps \
    && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]