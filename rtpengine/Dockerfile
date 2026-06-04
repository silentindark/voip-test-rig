# rtpengine on latest stable Debian, packages from https://deb.kamailio.org/rtpengine.html
ARG DEBIAN_TAG=stable-slim
FROM debian:${DEBIAN_TAG}

# rtpengine repo is versioned as rtpengine-mrXX.Y. mr26.0 publishes trixie
# packages for both amd64 and arm64 (mr13.5 is amd64-only on trixie). The Debian
# codename is auto-detected so this tracks `debian:stable`.
ARG RTPENGINE_REPO=rtpengine-mr26.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates gnupg curl \
 && . /etc/os-release \
 && curl -fsSL https://deb.kamailio.org/kamailiodebkey.gpg \
        | gpg --dearmor -o /usr/share/keyrings/kamailio.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/kamailio.gpg] http://deb.kamailio.org/${RTPENGINE_REPO} ${VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/rtpengine.list \
 && apt-get update && apt-get install -y --no-install-recommends \
        rtpengine-daemon \
 && apt-get purge -y curl gnupg && apt-get autoremove -y \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY rtpengine.conf /etc/rtpengine/rtpengine.conf

# ng control + media port range (must match rtpengine.conf)
EXPOSE 2223/udp 30000-30100/udp

ENTRYPOINT ["rtpengine", "--config-file=/etc/rtpengine/rtpengine.conf"]
