# WebRTC browser tests

Browser-driven tests for the rig's sip.js web client (`webapp/`). They run on
Sipfront inside a real Selenium browser, driven by a **`sipfront/agent-selenium`**
agent that the rig launches into pool-group **`webrtc`**
(`scripts/launch-webrtc-agent.sh`, wired into CI). The browser registers
`webrtc@rig.local` against Kamailio over WSS and places a call, exactly like a
human would.

## How it fits together

```
Selenium browser ──HTTPS──▶ webapp (sip.js)        (browser_url = https://172.30.10.50/)
       │  driven by                │ WSS
       ▼                           ▼
sf-agent-webrtc (agent-selenium)   kamailio  ──▶  asterisk (ooo announcement)
   pool-group "webrtc"             rtpengine bridges WebRTC DTLS-SRTP ⇄ G711
```

Unlike the baresip agents, the browser agent needs a Selenium browser, so it
joins its own pool-group `webrtc`; the Sipfront test's **browser step targets
that group** so it lands on the browser agent.

## The scripts

`*_test.js` here are the **reference/versioned** copies of the CodeceptJS scripts.
At runtime the Sipfront cloud pushes the script to the agent as the test's
`test_script` field — so editing the file here does **not** by itself change what
runs; you must also paste it into the Sipfront test.

- **`call-ooo_test.js`** — registers `webrtc@rig.local` and calls the Asterisk
  `ooo` announcement (calling-party-only; Asterisk answers, so no callee agent).

## Creating the Sipfront test (manual)

In project **voip-test-rig** (id 1659), agentpool **voip-test-rig**:

- **Scenario:** `browser_calling_party_only` (Desktop Browser → Calling Party Only).
- **Browser step:**
  - `browser_url` = `https://webapp.rig.local/` (the webapp; resolvable in-rig via a
    compose network alias and valid against the cert SAN)
  - `browser_name` = `Chrome`, OS Linux
  - **pool-group** = `webrtc`
  - `test_script` = contents of `call-ooo_test.js`
  - `credential_pool` = a pool with one entry: username `webrtc`, domain `rig.local`,
    auth_username `webrtc`, auth_password `webrtc123` (populates the `credentials`
    global the script reads)
- **Conditions:** caller has `CALL_OUTGOING`, plus `CALL_ESTABLISHED` /
  `CALL_RTPESTAB` (emitted by the agent's WebRTC analytics injection).

Add the test to the project so the CI `mode: project` run picks it up automatically.

## Notes

- The script overrides the webapp's `#server` to `wss://kamailio.rig.local:8443` so
  the in-rig browser reaches Kamailio by its cert-valid FQDN (the host default
  `wss://localhost:8443` is not reachable from inside the rig). Both
  `webapp.rig.local` and `kamailio.rig.local` resolve in-rig via docker-compose
  network aliases and match the cert SANs.
- The Selenium browser must trust the rig CA (self-signed) for the webapp HTTPS and
  the Kamailio WSS — `scripts/launch-webrtc-agent.sh` imports it into the Selenium
  container's system store and Chrome NSS DB.
- `webapp/www/index.html` loads sip.js from the jsDelivr CDN, so the Selenium
  container needs outbound internet (the rig-external bridge has NAT egress).
