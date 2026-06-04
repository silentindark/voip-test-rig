/*
 * Minimal SIP-over-WebRTC client for the rig, built on sip.js SimpleUser.
 * Registers to Kamailio over WSS and places calls to rig subscribers or the
 * Asterisk service URIs (moh / voicemail / ivr / attendant / ooo).
 *
 * sip.js 0.21 ships as ES modules only, so we import it (jsdelivr serves an
 * ESM bundle via the +esm endpoint) rather than relying on a UMD global.
 */
import { Web } from 'https://cdn.jsdelivr.net/npm/sip.js@0.21.2/+esm';

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
const logEl = $('log');

function log(msg) {
  const ts = new Date().toISOString().substring(11, 19);
  logEl.textContent += `[${ts}] ${msg}\n`;
  logEl.scrollTop = logEl.scrollHeight;
}
function setStatus(s) { statusEl.textContent = s; }

let simpleUser = null;

async function register() {
  if (simpleUser) { log('already connected'); return; }

  const server = $('server').value.trim();
  const domain = $('domain').value.trim();
  const user = $('user').value.trim();
  const pass = $('pass').value;
  const aor = `sip:${user}@${domain}`;

  const options = {
    aor,
    media: {
      constraints: { audio: true, video: false },
      remote: { audio: $('remoteAudio') }
    },
    userAgentOptions: {
      authorizationUsername: user,
      authorizationPassword: pass,
      displayName: user,
      logLevel: 'warn'
    },
    delegate: {
      onCallReceived: async () => { log('incoming call — answering'); await simpleUser.answer(); },
      onCallHangup: () => log('call ended'),
      onRegistered: () => setStatus(`registered as ${aor}`),
      onUnregistered: () => setStatus('unregistered'),
      onServerConnect: () => log('WSS connected'),
      onServerDisconnect: () => { setStatus('disconnected'); log('WSS disconnected'); }
    }
  };

  try {
    simpleUser = new Web.SimpleUser(server, options);
    setStatus('connecting…');
    log(`connecting to ${server}`);
    await simpleUser.connect();
    await simpleUser.register();
  } catch (e) {
    log(`register failed: ${e}`);
    setStatus('error');
    simpleUser = null;
  }
}

async function unregister() {
  if (!simpleUser) return;
  try { await simpleUser.unregister(); await simpleUser.disconnect(); }
  catch (e) { log(`disconnect error: ${e}`); }
  simpleUser = null;
  setStatus('disconnected');
}

async function call() {
  if (!simpleUser) { log('not registered'); return; }
  const target = $('target').value.trim();
  const domain = $('domain').value.trim();
  const uri = target.includes('@') ? `sip:${target}` : `sip:${target}@${domain}`;
  try {
    log(`calling ${uri}`);
    await simpleUser.call(uri);
  } catch (e) {
    log(`call failed: ${e}`);
  }
}

async function hangup() {
  if (!simpleUser) return;
  try { await simpleUser.hangup(); } catch (e) { log(`hangup error: ${e}`); }
}

$('btnRegister').addEventListener('click', register);
$('btnUnregister').addEventListener('click', unregister);
$('btnCall').addEventListener('click', call);
$('btnHangup').addEventListener('click', hangup);
document.querySelectorAll('.targets button').forEach((b) =>
  b.addEventListener('click', () => { $('target').value = b.dataset.t; })
);

log('ready — set your account and click Connect & Register');
