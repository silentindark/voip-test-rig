// WebRTC browser test: the rig's sip.js web client places an outbound call to
// the Asterisk `ooo` (out-of-office) announcement.
//
// This is the reference/versioned copy. It runs on Sipfront inside a Selenium
// browser driven by a `sipfront/agent-selenium` agent in pool-group "webrtc"
// (launched by scripts/launch-webrtc-agent.sh). At runtime the Sipfront cloud
// pushes this script as the test's `test_script`, sets `browser_url` to the
// webapp root, and injects the SIP account into the `credentials` global. To
// change the test, edit here and paste into the Sipfront test (see README.md).
//
// Helpers provided by the agent runtime: I.sendCallState(...), CallStates.*,
// and the `credentials` global (credentials.domain / .auth_username /
// .auth_password). Targeted element ids come from webapp/www/index.html.

Feature('webrtc');

Scenario('webrtc-call-ooo', async ({ I }) => {
  // Load the sip.js web client (browser_url points at the webapp root)
  I.amOnPage('');

  // Account form. Override the WSS server so the in-rig browser reaches Kamailio
  // directly (cert SAN includes 172.30.10.10); take the SIP account from the
  // credentials injected by the test's credential pool.
  I.waitForElement('#server', 15);
  I.fillField('#server', 'wss://172.30.10.10:8443');
  I.fillField('#domain', credentials.domain);
  I.fillField('#user', credentials.auth_username);
  I.fillField('#pass', credentials.auth_password);

  await I.sendCallState(CallStates.STATE_REGISTERING);

  // Connect & Register; wait until the status line confirms registration
  I.click('#btnRegister');
  I.waitForText('registered', 20, '#status');
  await I.sendCallState('REGISTER');

  // Place the outbound call to the out-of-office announcement
  I.waitForElement('#target', 15);
  I.fillField('#target', 'ooo');
  I.click('#btnCall');
  await I.sendCallState('CALL_OUTGOING');

  // Stay in the call so SIP/RTP (and the announcement) are measured
  I.wait(30);

  // Hang up
  I.click('#btnHangup');
  await I.sendCallState('ENDED_LOCAL');
});
