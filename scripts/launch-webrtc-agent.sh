#!/usr/bin/env bash
#
# Launch a browser (WebRTC) test agent into the rig's external network: a Selenium
# Chrome container plus a `sipfront/agent-selenium` agent that drives it. The agent
# joins pool-group "webrtc" so the Sipfront cloud routes browser steps to it (vs the
# baresip agents in default/customer/local from launch-agents.sh). The cloud pushes
# the codecept script + browser_url + credentials at run time; see tests/webrtc/.
#
# Self-contained: uses the same sipfront/agent image as the baresip agents (the
# CodeceptJS + remote-Selenium runtime already lives in it; the sibling
# agent-selenium project is just a local build of it plus a force-exit patch, not
# a published image) + selenium/standalone-chrome.
#
# Usage: scripts/launch-webrtc-agent.sh
# Env:   SF_POOL_ID, SF_POOL_SECRET (required), SF_IOTCORE_HOST, SF_SYS (dev|prod)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -f .env ] && { set -a; . ./.env; set +a; }

# sipfront/agent:dev carries browser-agent fixes not yet in :latest.
AGENT_IMAGE="${SF_AGENT_SELENIUM_IMAGE:-${SF_AGENT_IMAGE:-sipfront/agent:dev}}"
SELENIUM_IMAGE="${SF_SELENIUM_IMAGE:-selenium/standalone-chrome:latest}"
# The browser stack (Selenium Chrome, agent-selenium) is published amd64-only;
# pin the platform so it runs on arm64 hosts too (no-op on amd64 CI runners).
PLATFORM="${SF_BROWSER_PLATFORM:-linux/amd64}"
NETWORK="${RIG_NETWORK:-rig-external}"
SF_SYS="${SF_SYS:-dev}"
SELENIUM_NAME="sf-selenium"
AGENT_NAME="sf-agent-webrtc"

: "${SF_POOL_ID:?set SF_POOL_ID (CI: GitHub secret)}"
: "${SF_POOL_SECRET:?set SF_POOL_SECRET (CI: GitHub secret)}"

# MQTT broker by system (dev default).
if [ -z "${SF_IOTCORE_HOST:-}" ]; then
  SF_IOTCORE_HOST="mqtt.dev.sipfront.net"
  [ "${SF_SYS}" = "prod" ] && SF_IOTCORE_HOST="mqtt.sipfront.net"
fi

ca="${PWD}/certs/out/ca.crt"

# --- Selenium Chrome ---------------------------------------------------------
docker rm -f "${SELENIUM_NAME}" >/dev/null 2>&1 || true
echo "Starting ${SELENIUM_NAME} (${SELENIUM_IMAGE}) on ${NETWORK} ..."
ca_sel_mount=()
[ -f "${ca}" ] && ca_sel_mount=(-v "${ca}:/tmp/rig-ca.crt:ro")
docker run -d --init --pull always \
  --platform "${PLATFORM}" \
  --name "${SELENIUM_NAME}" --hostname "${SELENIUM_NAME}" \
  --network "${NETWORK}" \
  --shm-size=2g \
  "${ca_sel_mount[@]}" \
  "${SELENIUM_IMAGE}" >/dev/null

# Trust the rig CA inside the Selenium container so Chrome accepts the webapp's
# HTTPS and Kamailio's WSS (both signed by the rig's self-signed CA). Add it to the
# system store AND seluser's Chrome NSS DB. Non-fatal: the container stays up for
# debugging if this fails (the browser test would then hit cert errors).
if [ -f "${ca}" ]; then
  echo "Trusting rig CA inside ${SELENIUM_NAME} ..."
  sleep 2
  # certutil (libnss3-tools) ships in the selenium image, so no apt is needed —
  # this is just a fast cert import. Chrome on Linux validates against the user's
  # NSS DB (~/.pki/nssdb), so that import is the one that matters; the system
  # store is updated too for curl/openssl. The final `certutil -L | grep` makes
  # the exec's exit code reflect whether our CA actually landed.
  docker exec -u root "${SELENIUM_NAME}" bash -c '
    db=/home/seluser/.pki/nssdb
    cp /tmp/rig-ca.crt /usr/local/share/ca-certificates/rig-ca.crt
    update-ca-certificates >/dev/null 2>&1 || true
    install -d -o seluser -g seluser "$db"
    su seluser -s /bin/bash -c "certutil -d sql:$db -A -n rig-ca -t C,, -i /tmp/rig-ca.crt"
    su seluser -s /bin/bash -c "certutil -d sql:$db -L" 2>/dev/null | grep -q rig-ca
  ' && echo "rig CA trusted in ${SELENIUM_NAME}" \
    || echo "warn: could not import rig CA into ${SELENIUM_NAME} (browser TLS may fail)"
fi

# --- Browser agent (agent-selenium) ------------------------------------------
docker rm -f "${AGENT_NAME}" >/dev/null 2>&1 || true
echo "Starting ${AGENT_NAME} (${AGENT_IMAGE}) on ${NETWORK} (mqtt=${SF_IOTCORE_HOST}, group=webrtc) ..."
ca_mount=()
[ -f "${ca}" ] && ca_mount=(-v "${ca}:/usr/local/share/ca-certificates/rig-ca.crt:ro")
docker run -d --init --pull always \
  --platform "${PLATFORM}" \
  --name "${AGENT_NAME}" --hostname "${AGENT_NAME}" \
  --network "${NETWORK}" \
  --env SF_FORCE_LOCAL_IP=1 \
  --env SF_IOTCORE_HOST="${SF_IOTCORE_HOST}" \
  --env SF_POOL_ID="${SF_POOL_ID}" \
  --env SF_POOL_SECRET="${SF_POOL_SECRET}" \
  --env SF_LOGGER=console \
  --env SF_POOL_GROUP="webrtc" \
  --env SF_SELENIUM_HOST="${SELENIUM_NAME}" \
  --env SF_SELENIUM_PORT=4444 \
  --env SF_SELENIUM_PATH=/wd/hub \
  --env SF_CODECEPTJS_FORCE_EXIT=true \
  "${ca_mount[@]}" \
  "${AGENT_IMAGE}" >/dev/null

# Trust the rig CA for the agent's own TLS legs (non-fatal).
docker exec "${AGENT_NAME}" update-ca-certificates >/dev/null 2>&1 \
  || echo "warn: could not refresh CA store in ${AGENT_NAME}"

echo "WebRTC agent up: ${AGENT_NAME} (+ ${SELENIUM_NAME}). Logs: docker logs -f ${AGENT_NAME}"
