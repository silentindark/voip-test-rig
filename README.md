# voip-test-rig

[![Sipfront VoIP Rig CI Tests](https://github.com/sipfront/voip-test-rig/actions/workflows/rig.yml/badge.svg)](https://github.com/sipfront/voip-test-rig/actions/workflows/rig.yml)

A self-contained, **CI/CD-tested** VoIP microservice stack. Everything that defines
the system — the SIP proxy routing, the media relay, the application/announcement
logic, the WebRTC web client, and the subscriber database — lives as **plain editable
files in this repo**. Push a change and a GitHub runner stands the whole rig up in
Docker and tests it end-to-end with [Sipfront](https://sipfront.com).

```
                   ┌──────────────────────── GitHub runner ─────────────────────────┐
                   │                                                                │
  Sipfront cloud   │   external net (172.30.10.0/24)     internal net (.20.0/24)    │
  (dev) ◀── MQTT ──┼─▶ sf-agent ─SIP/RTP─▶ kamailio ─────────▶ asterisk             │
       443         │   (bridge mode)        │   ▲                  ▲                │
                   │                        │   │ ng:2223          │ media          │
                   │   webapp ──WSS────────▶┘   └─▶ rtpengine ◀────┘                │
                   │   (sip.js)                   (media bridge ext◀▶int)           │
                   │                              mysql (subscribers/location)      │
                   └────────────────────────────────────────────────────────────────┘
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

Once the rig is up, `scripts/launch-agents.sh` starts two `sipfront/agent:latest`
containers on the **external** docker network (with `SF_FORCE_LOCAL_IP=1` so each
advertises its docker IP — routable inside the rig). They dial **out** to the
Sipfront dev cloud over MQTT and register to a private **agent pool**. The CI
workflow then triggers two pre-defined Sipfront tests via the
[`sipfront/action-call-test`](https://github.com/sipfront/action-call-test) action:

- **basic call alice to bob** — agent-to-agent call routed by Kamailio.
- **basic call alice to asterisk-ooo** — call to a FreeSWITCH/Asterisk service URI.

The cloud backend drives the agents to REGISTER and place those calls against the
rig. (No project run yet — that's a later addition.)

Because the agents are local containers, the on-demand CA we generate is mounted into
them and trusted, so they accept the rig's TLS/WSS.

### Required GitHub secrets

| Secret | Purpose |
| --- | --- |
| `SF_API_PUBLIC_KEY` / `SF_API_SECRET_KEY` | Trigger the test via `action-call-test` |
| `SF_POOL_ID` / `SF_POOL_SECRET` | The dev agent pool the in-runner agents join |

The two test scenarios (`basic call alice to bob`, `basic call alice to
asterisk-ooo`) must already exist on dev and be bound to that pool.

## Run it locally

```bash
make run     # generate certs, build images, start the rig, wait until ready
make stop    # stop and remove the rig (containers, networks, volumes)
```

`make` (or `make help`) lists everything:

| Target | What it does |
| --- | --- |
| `make run` (`up`) | Generate certs (if missing), `docker compose up -d --build`, wait for readiness |
| `make stop` | `docker compose down -v` |
| `make down` | `stop` + also remove any local `sf-agent-*` containers |
| `make restart` | `down` then `run` |
| `make build` | Build all images |
| `make logs` | Follow logs from all services |
| `make ps` | Show container status |
| `make agent` | Run one Sipfront agent locally on the external net (needs `SF_POOL_ID`/`SF_POOL_SECRET` in `.env`) |
| `make certs` / `regen-certs` | Generate / force-regenerate the CA + server cert |
| `make clean` | `down` + delete `certs/out` |

Copy `.env.example` to `.env` first if you want to override defaults (subnets,
passwords) or use `make agent`.

> Kamailio (6.0) and rtpengine (mr26.0) build on Debian `stable` (currently
> trixie) from `deb.kamailio.org`. Asterisk builds on Debian **bullseye** (the
> last Debian release that ships the asterisk daemon — it was dropped in
> bookworm+) straight from the archive. No external tokens or accounts needed.

### Web client (browser on the host)

> **Trust the CA first.** The web client signals over **WSS**, and browsers do
> *not* prompt to accept a self-signed cert on a WebSocket — they just close it
> (error code `1006`). So you must trust the rig CA up front:
> ```bash
> # macOS:
> sudo security add-trusted-cert -d -r trustRoot \
>   -k /Library/Keychains/System.keychain certs/out/ca.crt
> ```
> (Linux: copy `certs/out/ca.crt` into your browser/OS trust store.) Alternatively,
> open `https://localhost:8443/` once and click through the warning — you'll get a
> `404` page, which means the WSS endpoint works; the cert exception then lets the
> WebSocket connect.

Open `https://localhost:8081/` and register as `webrtc@rig.local` / `webrtc123`.
The WSS server defaults to `wss://localhost:8443` (Kamailio's WSS port is published
to the host; the cert is valid for `localhost`). Call `moh`, `voicemail`, `ivr`,
`attendant`, `ooo`, or another subscriber (`alice` / `bob`).

### Softphone

All SIP/RTP ports are published to `localhost`, so point a softphone at
`localhost:5060` (UDP/TCP) or `localhost:5061` (TLS), domain `rig.local`, as
`alice@rig.local` / `bob@rig.local`. Seeded passwords are in
`kamailio/initdb.d/10-seed.sql`.

> **macOS / Windows:** reach the rig via these **published `localhost` ports** —
> the docker container IPs (`172.30.10.x`) are not routable from the host. On
> **Linux** you can instead hit the container IPs directly and map
> `kamailio.rig.local` → `172.30.10.10` in `/etc/hosts`.

To exercise the full Sipfront path locally, run one agent against a personal dev
pool (set `SF_POOL_ID`/`SF_POOL_SECRET` in `.env`):

```bash
make agent
```

## Status / roadmap

- **Phase 1 (current):** SIP register/auth/location, routing to Asterisk service
  URIs, media bridged external↔internal via rtpengine, and a human-usable WSS web
  client.
- **Phase 2 (planned):** automated in-runner headless-browser WebRTC test so the
  browser↔agent DTLS-SRTP media path is CI-tested too.

> Note: rtpengine runs **userspace-only** (`table = -1`) because GitHub runners don't
> provide the in-kernel forwarding module. Fine for functional testing.
