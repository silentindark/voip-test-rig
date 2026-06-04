# voip-test-rig

A self-contained, **CI/CD-tested** VoIP microservice stack. Everything that defines
the system — the SIP proxy routing, the media relay, the application/announcement
logic, the WebRTC web client, and the subscriber database — lives as **plain editable
files in this repo**. Push a change and a GitHub runner stands the whole rig up in
Docker and tests it end-to-end with [Sipfront](https://sipfront.com).

```
                   ┌──────────────────────── GitHub runner ───────────────────────┐
                   │                                                               │
  Sipfront cloud   │   external net (172.30.10.0/24)     internal net (.20.0/24)   │
  (dev) ◀── MQTT ──┼─▶ sf-agent ─SIP/RTP─▶ kamailio ─────────▶ asterisk           │
       443         │   (bridge mode)        │   ▲                  ▲                │
                   │                        │   │ ng:2223          │ media          │
                   │   webapp ──WSS────────▶┘   └─▶ rtpengine ◀────┘                │
                   │   (sip.js)                   (media bridge ext◀▶int)           │
                   │                              mysql (subscribers/location)      │
                   └───────────────────────────────────────────────────────────────┘
```

- **kamailio** — SIP proxy: registration, MySQL digest auth, location lookup, and
  routing. Special service URIs (`moh`, `voicemail`, `ivr`, `attendant`, `ooo`) are
  routed to Asterisk. Terminates WSS for the web client.
- **asterisk** — application/announcement server (music-on-hold, voicemail, IVR /
  auto-attendant, out-of-office), installed straight from the Debian archive.
- **rtpengine** — media relay; **bridges RTP between the external and internal
  networks** so signaling and media topologies stay separate. Runs userspace-only.
- **webapp** — a minimal [sip.js](https://sipjs.com) SIP-over-WebRTC client served
  over HTTPS; registers and places calls over WSS to Kamailio.
- **mysql** — Kamailio's `subscriber` and `location` backend, seeded on first boot.

The two networks model a typical voice deployment: clients and the web app live on the
"external" edge, application/DB services live "internal", and rtpengine is the only
component that bridges media across the boundary.

## The develop → push → test loop

1. Edit any of the **editable config surface**:
   - `kamailio/kamailio.cfg`, `kamailio/tls.cfg` — proxy routing / auth / TLS
   - `kamailio/initdb.d/*.sql` — subscribers and DB schema
   - `rtpengine/rtpengine.conf` — media relay
   - `asterisk/extensions.conf`, `asterisk/pjsip.conf` — app logic
   - `webapp/www/*` — the WebRTC client
   - `docker-compose.yml` — topology
2. Commit and push.
3. `.github/workflows/rig.yml` runs: it generates certs, brings the rig up, launches
   Sipfront agents into the external network, and triggers a Sipfront test/project run.
4. The job summary links to the Sipfront **report** with pass/fail for the
   REGISTER / INVITE / service-URI scenarios.

## How testing works

Sipfront agents are launched in the runner from the public `sipfront/agent:latest`
image, attached to the **external** docker network in bridge mode (which also
exercises Kamailio's far-end NAT handling). They dial **out** to the Sipfront dev
cloud over MQTT and register to a private **agent pool**. A pre-defined Sipfront test —
bound to that pool — is then triggered via the
[`sipfront/action-call-test`](https://github.com/sipfront/action-call-test) action;
the cloud backend drives the agents to REGISTER and place calls against the rig.

Because the agents are local containers, the on-demand CA we generate is mounted into
them and trusted, so they accept the rig's TLS/WSS.

### Required GitHub secrets

| Secret | Purpose |
| --- | --- |
| `SF_API_PUBLIC_KEY` / `SF_API_SECRET_KEY` | Trigger the test via `action-call-test` |
| `SF_POOL_ID` / `SF_POOL_SECRET` | The dev agent pool the in-runner agents join |

The Sipfront test/scenario must already exist on dev and be bound to that pool.

## Run it locally

```bash
cp .env.example .env          # optional; sensible defaults are built in
bash certs/gen-certs.sh       # writes certs/out/{ca.crt,server.key,server.crt}
docker compose up -d --build
bash scripts/wait-for-rig.sh
```

> Kamailio (6.0) and rtpengine (mr26.0) build on Debian `stable` (currently
> trixie) from `deb.kamailio.org`. Asterisk builds on Debian **bullseye** (the
> last Debian release that ships the asterisk daemon — it was dropped in
> bookworm+) straight from the archive. No external tokens or accounts needed.

Then point a softphone at `kamailio.rig.local:5060` (add a hosts entry to
`172.30.10.10`) as `alice@rig.local` / `bob@rig.local`, or open the web client at
`https://172.30.10.50/` (trust `certs/out/ca.crt`) and register as `webrtc@rig.local`.
Call `moh@rig.local`, `voicemail@rig.local`, `ivr@rig.local`, `ooo@rig.local`, or
another subscriber. Seeded test passwords are in `kamailio/initdb.d/10-seed.sql`.

To exercise the full Sipfront path locally, run one agent against a personal dev pool:

```bash
docker run --init --pull always --network rig-external \
  -e SF_POOL_ID=... -e SF_POOL_SECRET=... -e SF_IOTCORE_HOST=mqtt.dev.sipfront.net \
  -v "$PWD/certs/out/ca.crt:/usr/local/share/ca-certificates/rig-ca.crt:ro" \
  --add-host kamailio.rig.local:172.30.10.10 \
  sipfront/agent:latest
```

Tear down with `docker compose down -v`.

## Status / roadmap

- **Phase 1 (current):** SIP register/auth/location, routing to Asterisk service
  URIs, media bridged external↔internal via rtpengine, and a human-usable WSS web
  client.
- **Phase 2 (planned):** automated in-runner headless-browser WebRTC test so the
  browser↔agent DTLS-SRTP media path is CI-tested too.

> Note: rtpengine runs **userspace-only** (`table = -1`) because GitHub runners don't
> provide the in-kernel forwarding module. Fine for functional testing.
