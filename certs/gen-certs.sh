#!/usr/bin/env bash
#
# Generate an on-demand CA and a single multi-SAN server certificate for the rig.
# The server cert is shared by Kamailio (TLS/WSS) and the webapp (HTTPS); the CA is
# mounted into the Sipfront agent containers and trusted so they accept the rig's TLS.
#
# Idempotent: re-running regenerates everything under certs/out/.
#
# Override the SAN addresses to match your compose IPs if you change the subnets:
#   KAMAILIO_EXT_IP, WEBAPP_EXT_IP
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${here}/out"
mkdir -p "${out}"

SIP_DOMAIN="${SIP_DOMAIN:-rig.local}"
KAMAILIO_EXT_IP="${KAMAILIO_EXT_IP:-172.30.10.10}"
WEBAPP_EXT_IP="${WEBAPP_EXT_IP:-172.30.10.50}"
DAYS="${CERT_DAYS:-3650}"

ca_key="${out}/ca.key"
ca_crt="${out}/ca.crt"
srv_key="${out}/server.key"
srv_csr="${out}/server.csr"
srv_crt="${out}/server.crt"
ext="${out}/server.ext"

echo "==> Generating CA"
openssl genrsa -out "${ca_key}" 4096 2>/dev/null
openssl req -x509 -new -nodes -key "${ca_key}" -sha256 -days "${DAYS}" \
  -subj "/C=AT/O=voip-test-rig/CN=voip-test-rig Root CA" \
  -out "${ca_crt}"

echo "==> Generating server key + CSR"
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
DNS.3 = freeswitch.${SIP_DOMAIN}
DNS.4 = localhost
IP.1  = ${KAMAILIO_EXT_IP}
IP.2  = ${WEBAPP_EXT_IP}
IP.3  = 127.0.0.1
EOF

echo "==> Signing server cert with CA"
openssl x509 -req -in "${srv_csr}" -CA "${ca_crt}" -CAkey "${ca_key}" \
  -CAcreateserial -days "${DAYS}" -sha256 -extfile "${ext}" -out "${srv_crt}"

# Kamailio's tls module likes a combined chain available too.
cat "${srv_crt}" "${ca_crt}" > "${out}/server-chain.crt"

rm -f "${srv_csr}" "${ext}" "${out}/ca.srl"

echo "==> Done. Files in ${out}:"
ls -1 "${out}"
echo
echo "SANs: kamailio.${SIP_DOMAIN}, webapp.${SIP_DOMAIN}, freeswitch.${SIP_DOMAIN}, ${KAMAILIO_EXT_IP}, ${WEBAPP_EXT_IP}"
