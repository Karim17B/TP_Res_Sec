FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      exim4-daemon-light \
      dovecot-pop3d \
      openssl \
      ssl-cert \
      telnet \
      openbsd-inetd \
      inetutils-telnetd \
      tcpd \
      netcat-openbsd \
      mailutils \
      iproute2 \
      iputils-ping \
      net-tools \
      procps \
      tcpdump \
      less \
    && rm -rf /var/lib/apt/lists/*

# exim4 refuse de demarrer sans /etc/mailname coherent.
RUN echo 'mail.tp.local' > /etc/mailname

COPY update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf
COPY 99-tp.conf /etc/dovecot/conf.d/99-tp.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Comptes de test. Mots de passe volontairement triviaux, c'est un lab.
RUN useradd -m -s /bin/bash alice && echo 'alice:alice' | chpasswd \
 && useradd -m -s /bin/bash bob   && echo 'bob:bob'     | chpasswd

# --- TELNET (§2 du sujet) ----------------------------------------------------
# inetutils-telnetd s'enregistre dans /etc/inetd.conf en '#<off>#' (desactive).
# update-inetd --enable retire ce marqueur pour que le superdaemon serve le 23.
RUN update-inetd --enable telnet
# Compte de test dedie telnet (login qui circulera EN CLAIR, cf. §7).
RUN useradd -m -s /bin/bash tptelnet && echo 'tptelnet:tptelnet123' | chpasswd

ENV SMTP_PORT=25
ENV POP3_PORT=110
ENV TELNET_PORT=23

# Point 4.a : "desactiver l'un des trois serveurs, au choix".
ENV ENABLE_SMTP=1
ENV ENABLE_POP3=1
ENV ENABLE_TELNET=1

EXPOSE 23 25 110

# Un conteneur "Up" ne prouve pas que les deux services ecoutent.
HEALTHCHECK --interval=10s --timeout=5s --start-period=25s --retries=3 \
  CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]