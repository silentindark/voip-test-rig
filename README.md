# voip-test-rig

[![Sipfront VoIP Rig CI Tests](https://github.com/sipfront/voip-test-rig/actions/workflows/rig.yml/badge.svg)](https://github.com/sipfront/voip-test-rig/actions/workflows/rig.yml)

A **reference implementation of a typical telco stack** — Kamailio, Asterisk,
rtpengine, MySQL and a [sip.js](https://sipjs.com) WebRTC client — wired so the
whole thing is **automatically tested in a throwaway GitHub runner on every push**,
using [Sipfront](https://sipfront.com) agents for both **SIP and WebRTC**.

Everything that defines the system lives as **plain editable files in this repo**.
Push a change and a runner stands the rig up in Docker, launches Sipfront test
agents into it, runs the full test suite end-to-end, and tears it all down.

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

## Components

- **kamailio** — SIP proxy: registration, MySQL digest auth, location lookup. Forces
  **every** call through Asterisk so the app server owns the media path, and terminates
  WSS for the web client.
- **asterisk** — application/announcement server (music-on-hold, voicemail, IVR /
  attendant, out-of-office). Sits in the media path for all calls.
- **rtpengine** — media relay between the two networks. Transcodes endpoint codecs
  (Opus, G.722, …) to the G.711 Asterisk speaks, and bridges WebRTC DTLS-SRTP ⇄ plain
  RTP. Userspace-only (`table = -1`), since runners lack the in-kernel module.
- **webapp** — a minimal sip.js SIP-over-WebRTC client served over HTTPS; registers and
  calls over WSS to Kamailio.
- **mysql** — Kamailio's subscriber/location store, seeded on first boot from
  `kamailio/initdb.d/*.sql`.

Two docker networks model a real deployment: clients and the web app on the
**external** edge, app/DB services **internal**, with rtpengine the only bridge across.
The editable surface is the config under `kamailio/`, `rtpengine/`, `asterisk/`,
`webapp/`, and `docker-compose.yml`.

## How it's tested

Each push runs `.github/workflows/rig.yml`: generate an on-demand CA + certs →
`docker compose up` the rig → launch agents → run the Sipfront **`voip-test-rig`
project** (every test in it) → report pass/fail in the job summary → tear everything
down. The job fails if any test fails.

Agents are plain containers on the external network that dial **out** to the Sipfront
cloud over MQTT and join a private **agent pool**; the cloud then drives them to
register and place calls against the rig:

- **Two SIP agents** (`scripts/launch-agents.sh`) for the SIP/RTP tests — basic calls,
  codecs (Opus/G.722), DTMF, hold/retrieve, TLS scan, etc.
- **One browser agent** (`scripts/launch-webrtc-agent.sh`) — a Selenium Chrome plus a
  `sipfront/agent` joined to pool-group **`webrtc`**, which loads the sip.js client in a
  real browser and places WebRTC calls. It trusts the rig CA and reaches the stack by
  its cert-valid FQDNs (`webapp.rig.local`, `kamailio.rig.local`). Reference scripts and
  the cloud-test setup are in [`tests/webrtc/`](tests/webrtc/).

The on-demand CA is mounted into every agent (and the browser) so they accept the rig's
self-signed TLS/WSS.

### Required GitHub secrets

| Secret | Purpose |
| --- | --- |
| `SF_API_PUBLIC_KEY` / `SF_API_SECRET_KEY` | Trigger the project run (`sipfront/action-call-test`) |
| `SF_POOL_ID` / `SF_POOL_SECRET` | The Sipfront agent pool the in-runner agents join |

The `voip-test-rig` project and its tests must already exist on Sipfront and be bound to
that pool.

## Run it locally

```bash
make run            # certs + build + start the rig, wait until ready
make agent          # launch 2 SIP agents                         (needs SF_POOL_* in .env)
make webrtc-agent   # launch the WebRTC browser agent + Selenium   (needs SF_POOL_* in .env)
make agent-logs     # follow an agent (AGENT=sf-agent-1 | sf-agent-webrtc | sf-selenium)
make down           # stop the rig and remove the agents
```

`make help` lists every target. Copy `.env.example` to `.env` and set
`SF_POOL_ID`/`SF_POOL_SECRET` (optionally override subnets/passwords) before launching
agents.

> Build notes: Kamailio (6.0) and rtpengine (mr26.0) build on Debian stable from
> `deb.kamailio.org`; Asterisk on Debian **bullseye** (the last release shipping the
> daemon). No external tokens or accounts needed.

## Use the rig by hand

**Web client** — open `https://localhost:8081/` and register `webrtc@rig.local` /
`webrtc123` (WSS defaults to `wss://localhost:8443`). Call `moh`, `voicemail`, `ivr`,
`attendant`, `ooo`, or a subscriber (`alice` / `bob`).

> **Trust the CA first.** Browsers silently drop a WSS to an untrusted cert (close
> `1006`), so trust the rig CA up front. macOS:
> ```bash
> sudo security add-trusted-cert -d -r trustRoot \
>   -k /Library/Keychains/System.keychain certs/out/ca.crt
> ```
> (Linux: add `certs/out/ca.crt` to your OS/browser trust store.)

**Softphone** — point at `localhost:5060` (UDP/TCP) or `localhost:5061` (TLS), domain
`rig.local`, as `alice` / `bob` (seeded passwords in `kamailio/initdb.d/10-seed.sql`).
On macOS/Windows use these published `localhost` ports — the container IPs
(`172.30.10.x`) aren't routable from the host.
