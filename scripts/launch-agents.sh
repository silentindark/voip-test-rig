#!/usr/bin/env bash
#
# Launch N Sipfront agents into the rig's external network. They register to the
# CI agent pool (SF_POOL_ID/SF_POOL_SECRET) and connect OUT to the Sipfront cloud
# over MQTT; the cloud then drives them to run tests against the rig.
#
# SF_FORCE_LOCAL_IP=1 makes each agent advertise its docker IP instead of looking
# up the runner's public IP — essential here so its SIP Contact is routable
# inside the rig (otherwise calls fail far-end-NAT style).
#
# Usage: scripts/launch-agents.sh [count]
# Env:   SF_POOL_ID, SF_POOL_SECRET (required), SF_IOTCORE_HOST, SF_SYS (dev|prod)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -f .env ] && { set -a; . ./.env; set +a; }

COUNT="${1:-2}"
IMAGE="${SF_AGENT_IMAGE:-sipfront/agent:latest}"
NETWORK="${RIG_NETWORK:-rig-external}"
SF_SYS="${SF_SYS:-dev}"

: "${SF_POOL_ID:?set SF_POOL_ID (CI: GitHub secret)}"
: "${SF_POOL_SECRET:?set SF_POOL_SECRET (CI: GitHub secret)}"

# MQTT broker by system (dev default).
if [ -z "${SF_IOTCORE_HOST:-}" ]; then
  SF_IOTCORE_HOST="mqtt.dev.sipfront.net"
  [ "${SF_SYS}" = "prod" ] && SF_IOTCORE_HOST="mqtt.sipfront.net"
fi

ca="${PWD}/certs/out/ca.crt"

for i in $(seq 1 "${COUNT}"); do
  name="sf-agent-${i}"
  docker rm -f "${name}" >/dev/null 2>&1 || true

  ca_mount=()
  [ -f "${ca}" ] && ca_mount=(-v "${ca}:/usr/local/share/ca-certificates/rig-ca.crt:ro")

  echo "Starting ${name} on ${NETWORK} (mqtt=${SF_IOTCORE_HOST}) ..."
  docker run -d --init --pull always \
    --name "${name}" --hostname "${name}" \
    --network "${NETWORK}" \
    --env SF_FORCE_LOCAL_IP=1 \
    --env SF_IOTCORE_HOST="${SF_IOTCORE_HOST}" \
    --env SF_POOL_ID="${SF_POOL_ID}" \
    --env SF_POOL_SECRET="${SF_POOL_SECRET}" \
    --env SF_LOGGER=console \
    --env SF_POOL_GROUP="default,customer,local" \
    "${ca_mount[@]}" \
    "${IMAGE}" >/dev/null

  # Trust the rig CA for the agent's TLS/WSS legs (non-fatal).
  docker exec "${name}" update-ca-certificates >/dev/null 2>&1 \
    || echo "warn: could not refresh CA store in ${name}"
done

echo "${COUNT} agent(s) started: $(seq -s' ' -f 'sf-agent-%g' 1 "${COUNT}")"
