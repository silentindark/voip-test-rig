-- Test subscribers for the rig. Edit/extend these and push to change who can
-- register. ha1 = MD5(username:domain:password); we let MySQL compute it so the
-- plaintext stays readable here for the demo.
--
-- NOTE: the domain MUST match SIP_DOMAIN in .env, the cert SAN, and the webapp
-- realm (all `rig.local` by default).

USE kamailio;

INSERT INTO subscriber (username, domain, password, ha1, ha1b) VALUES
  ('alice',  'rig.local', 'alice123',  MD5('alice:rig.local:alice123'),   MD5('alice@rig.local:rig.local:alice123')),
  ('bob',    'rig.local', 'bob123',    MD5('bob:rig.local:bob123'),       MD5('bob@rig.local:rig.local:bob123')),
  ('webrtc', 'rig.local', 'webrtc123', MD5('webrtc:rig.local:webrtc123'), MD5('webrtc@rig.local:rig.local:webrtc123'));
