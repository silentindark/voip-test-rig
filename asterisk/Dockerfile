# Asterisk straight from the Debian archive — no external repo, no token.
# NOTE: the asterisk daemon was dropped from Debian after bullseye (it's absent
# from bookworm/trixie), so bullseye is the last Debian release that ships it
# (Asterisk 16 LTS). This image therefore pins bullseye independently of the
# trixie-based kamailio/rtpengine images.
ARG DEBIAN_TAG=bullseye-slim
FROM debian:${DEBIAN_TAG}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends asterisk \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/asterisk \
 && chown asterisk:asterisk /var/run/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk

# Override only the three files that define this rig's behaviour; the rest of
# the Debian default config provides a clean, bootable Asterisk.
COPY modules.conf    /etc/asterisk/modules.conf
COPY pjsip.conf      /etc/asterisk/pjsip.conf
COPY extensions.conf /etc/asterisk/extensions.conf

EXPOSE 5060/udp

# Foreground, verbose, no console colors.
ENTRYPOINT ["asterisk", "-f", "-vvvn"]
