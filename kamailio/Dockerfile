# Kamailio on latest stable Debian, packages from https://deb.kamailio.org
ARG DEBIAN_TAG=stable-slim
FROM debian:${DEBIAN_TAG}

# Kamailio apt repo is versioned (kamailio60 = 6.0, etc). 6.0 publishes packages
# for Debian trixie (current stable); the codename is auto-detected. Bump as the
# Debian stable / Kamailio release moves on.
ARG KAMAILIO_VERSION=6.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates gnupg curl \
 && . /etc/os-release \
 && KVER="$(echo "${KAMAILIO_VERSION}" | tr -d '.')" \
 && curl -fsSL https://deb.kamailio.org/kamailiodebkey.gpg \
        | gpg --dearmor -o /usr/share/keyrings/kamailio.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/kamailio.gpg] http://deb.kamailio.org/kamailio${KVER} ${VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/kamailio.list \
 && apt-get update && apt-get install -y --no-install-recommends \
        kamailio \
        kamailio-mysql-modules \
        kamailio-tls-modules \
        kamailio-websocket-modules \
        kamailio-extra-modules \
 && apt-get purge -y curl gnupg && apt-get autoremove -y \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Runtime dir for the ctl binrpc socket (so `kamcmd` works via docker exec).
RUN mkdir -p /run/kamailio

COPY kamailio.cfg /etc/kamailio/kamailio.cfg
COPY tls.cfg      /etc/kamailio/tls.cfg

# SIP UDP/TCP, TLS, and WSS (secure WebSocket) on the external leg.
EXPOSE 5060/udp 5060/tcp 5061/tcp 8443/tcp

# Foreground, log to stderr.
ENTRYPOINT ["kamailio", "-DD", "-E", "-f", "/etc/kamailio/kamailio.cfg"]
