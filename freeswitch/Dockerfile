# FreeSWITCH on latest stable Debian, installed the simplest documented way:
#   https://developer.signalwire.com/freeswitch/FreeSWITCH-Explained/Installation/
# The SignalWire apt repo requires a free Personal Access Token, passed as a
# build-arg (SIGNALWIRE_TOKEN). Shell-form RUN keeps the token out of image
# history (only the literal "$SIGNALWIRE_TOKEN" text is recorded).
ARG DEBIAN_TAG=stable-slim
FROM debian:${DEBIAN_TAG}

ARG SIGNALWIRE_TOKEN
ENV DEBIAN_FRONTEND=noninteractive

RUN test -n "${SIGNALWIRE_TOKEN}" || { echo "ERROR: SIGNALWIRE_TOKEN build-arg is required (free token from https://signalwire.com)"; exit 1; } \
 && apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && . /etc/os-release \
 && curl --fail -u "signalwire:${SIGNALWIRE_TOKEN}" \
      -o /usr/share/keyrings/signalwire-freeswitch-repo.gpg \
      https://freeswitch.signalwire.com/repo/deb/debian-release/signalwire-freeswitch-repo.gpg \
 && echo "machine freeswitch.signalwire.com login signalwire password ${SIGNALWIRE_TOKEN}" > /etc/apt/auth.conf \
 && chmod 600 /etc/apt/auth.conf \
 && echo "deb [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/debian-release/ ${VERSION_CODENAME} main" \
      > /etc/apt/sources.list.d/freeswitch.list \
 && apt-get update && apt-get install -y --no-install-recommends freeswitch-meta-vanilla \
 && rm -f /etc/apt/auth.conf \
 && apt-get purge -y curl gnupg && apt-get autoremove -y \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Override only the two files that define this rig's behaviour; the rest of the
# vanilla config provides a clean, bootable FreeSWITCH.
COPY sip_profiles/internal.xml /etc/freeswitch/sip_profiles/internal.xml
COPY dialplan/public.xml       /etc/freeswitch/dialplan/public.xml

EXPOSE 5060/udp 5060/tcp

# Foreground, no NAT auto-detection (no internet/STUN in the rig).
ENTRYPOINT ["freeswitch", "-nf", "-nonat"]
