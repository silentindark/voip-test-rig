# Asterisk straight from the Debian archive — no external repo, no token.
# NOTE: the asterisk daemon was dropped from Debian after bullseye (it's absent
# from bookworm/trixie), so bullseye is the last Debian release that ships it
# (Asterisk 16 LTS). This image therefore pins bullseye independently of the
# trixie-based kamailio/rtpengine images.
ARG DEBIAN_TAG=bullseye-slim
FROM debian:${DEBIAN_TAG}

ENV DEBIAN_FRONTEND=noninteractive

# asterisk + a ulaw core-sounds set (for the hold announcement). Seed the MoH
# directory with one bundled example prompt; ulaw needs no extra codec since
# Asterisk already speaks ulaw/alaw toward rtpengine.
RUN apt-get update && apt-get install -y --no-install-recommends \
        asterisk asterisk-core-sounds-en-ulaw \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/asterisk /var/lib/asterisk/moh \
 && cp /usr/share/asterisk/sounds/en/demo-congrats.ulaw /var/lib/asterisk/moh/ \
 && chown -R asterisk:asterisk /var/run/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk

# Override only the files that define this rig's behaviour; the rest of the
# Debian default config provides a clean, bootable Asterisk.
COPY modules.conf     /etc/asterisk/modules.conf
COPY pjsip.conf       /etc/asterisk/pjsip.conf
COPY extensions.conf  /etc/asterisk/extensions.conf
COPY musiconhold.conf /etc/asterisk/musiconhold.conf

EXPOSE 5060/udp

# Foreground, verbose, no console colors.
ENTRYPOINT ["asterisk", "-f", "-vvvn"]
