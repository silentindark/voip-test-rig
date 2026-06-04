#!/usr/bin/env bash
#
# Generate the rig's CA and a multi-SAN server certificate.
#
# The **CA is persistent**: it is only (re)created when missing or within 7 days
# of expiry, and is issued with a 5-year validity. That way, once you trust
# certs/out/ca.crt in your browser/OS, you don't have to re-accept it on every
# run (important for the WebRTC web client, whose WSS handshake silently fails on
# an untrusted cert). The server leaf is shared by Kamailio (TLS/WSS) and the
# webapp (HTTPS) and is re-signed when missing/expiring or when the CA changed.
#
# Force a full regen with: make regen-certs   (or: rm -rf certs/out && this script)
#
# Override SANs to match your compose IPs if you change subnets:
#   KAMAILIO_EXT_IP, WEBAPP_EXT_IP
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${here}/out"
mkdir -p "${out}"

SIP_DOMAIN="${SIP_DOMAIN:-rig.local}"
KAMAILIO_EXT_IP="${KAMAILIO_EXT_IP:-172.30.10.10}"
WEBAPP_EXT_IP="${WEBAPP_EXT_IP:-172.30.10.50}"

CA_DAYS="${CA_DAYS:-1825}"          # 5 years
LEAF_DAYS="${LEAF_DAYS:-1825}"      # within the CA's lifetime
RENEW_SECS=$(( 7 * 24 * 3600 ))     # regenerate if expiring within 7 days

ca_key="${out}/ca.key"
ca_crt="${out}/ca.crt"
srv_key="${out}/server.key"
srv_csr="${out}/server.csr"
srv_crt="${out}/server.crt"
ext="${out}/server.ext"

# True if a cert exists and is NOT expiring within RENEW_SECS.
cert_fresh() { [ -f "$1" ] && openssl x509 -checkend "${RENEW_SECS}" -noout -in "$1" >/dev/null 2>&1; }

ca_regenerated=0
if [ -f "${ca_key}" ] && cert_fresh "${ca_crt}"; then
  echo "==> Reusing existing CA (valid for >7 days)"
else
  echo "==> Generating CA (valid ${CA_DAYS} days)"
  openssl genrsa -out "${ca_key}" 4096 2>/dev/null
  openssl req -x509 -new -nodes -key "${ca_key}" -sha256 -days "${CA_DAYS}" \
    -subj "/C=AT/O=voip-test-rig/CN=voip-test-rig Root CA" \
    -out "${ca_crt}"
  ca_regenerated=1
fi

if [ "${ca_regenerated}" -eq 0 ] && cert_fresh "${srv_crt}" && [ -f "${srv_key}" ]; then
  echo "==> Reusing existing server certificate"
else
  echo "==> Generating server certificate (valid ${LEAF_DAYS} days)"
  openssl genrsa -out "${srv_key}" 2048 2>/dev/null
  openssl req -new -key "${srv_key}" \
    -subj "/C=AT/O=voip-test-rig/CN=kamailio.${SIP_DOMAIN}" \
    -out "${srv_csr}"

  cat > "${ext}" <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kamailio.${SIP_DOMAIN}
DNS.2 = webapp.${SIP_DOMAIN}
DNS.3 = asterisk.${SIP_DOMAIN}
DNS.4 = localhost
IP.1  = ${KAMAILIO_EXT_IP}
IP.2  = ${WEBAPP_EXT_IP}
IP.3  = 127.0.0.1
EOF

  openssl x509 -req -in "${srv_csr}" -CA "${ca_crt}" -CAkey "${ca_key}" \
    -CAcreateserial -days "${LEAF_DAYS}" -sha256 -extfile "${ext}" -out "${srv_crt}"

  # Kamailio's tls module is happiest with the full chain available too.
  cat "${srv_crt}" "${ca_crt}" > "${out}/server-chain.crt"

  rm -f "${srv_csr}" "${ext}" "${out}/ca.srl"
fi

echo "==> Files in ${out}:"
ls -1 "${out}"
echo
echo "CA expires:     $(openssl x509 -enddate -noout -in "${ca_crt}" | cut -d= -f2)"
echo "Server expires: $(openssl x509 -enddate -noout -in "${srv_crt}" | cut -d= -f2)"
echo "SANs: kamailio.${SIP_DOMAIN}, webapp.${SIP_DOMAIN}, asterisk.${SIP_DOMAIN}, ${KAMAILIO_EXT_IP}, ${WEBAPP_EXT_IP}, localhost"
