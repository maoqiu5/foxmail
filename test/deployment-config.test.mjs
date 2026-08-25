import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

function read(path) {
  return fs.readFileSync(path, "utf8");
}

test("mail data is persistent and IMAPS is not published publicly", () => {
  const compose = read("deploy/docker-compose.yml");

  assert.match(compose, /\/data_n006\/mail-archive\/mail:\/srv\/mail/);
  assert.match(compose, /network_mode:\s*"service:tailscale"/);
  assert.doesNotMatch(compose, /(?:^|[-\s'"])(?:25|465|587):/m);
});

test("credentials are mounted as files", () => {
  const compose = read("deploy/docker-compose.yml");

  assert.match(compose, /wps_password:ro/);
  assert.match(compose, /archive_password:ro/);
  assert.doesNotMatch(compose, /WPS_PASSWORD\s*:/);
  assert.doesNotMatch(compose, /ARCHIVE_PASSWORD\s*:/);
});

test("Dovecot requires TLS and stores Maildir on the persistent mount", () => {
  const dovecot = read("deploy/dovecot/dovecot.conf");

  assert.match(dovecot, /ssl = required/);
  assert.match(dovecot, /auth_allow_cleartext = no/);
  assert.match(dovecot, /mail_path = \/srv\/mail\/%\{user\}\/Maildir/);
  assert.match(dovecot, /auth_mechanisms = plain login/);
});

test("Dovecot supports Foxmail's single WPS credential for incoming IMAP", () => {
  const compose = read("deploy/docker-compose.yml");
  const entrypoint = read("deploy/dovecot/entrypoint.sh");

  assert.match(compose, /dovecot:[\s\S]*wps_password:\/run\/secrets\/wps_password:ro/);
  assert.match(entrypoint, /brian\.lu@cimcwetrans\.com/);
  assert.match(entrypoint, /cat \/run\/secrets\/wps_password/);
  assert.match(entrypoint, /\/srv\/mail\/archive\/Maildir/);
});

test("scheduler runs every 180 seconds without overlap", () => {
  const sync = read("deploy/sync/run-sync-loop.sh");

  assert.match(sync, /sleep 180/);
  assert.match(sync, /flock -n/);
});

test("imapsync is copy-only and reads passwords from files", () => {
  const sync = read("deploy/sync/run-sync-loop.sh");

  assert.match(sync, /--host1 mail\.ksomail\.com/);
  assert.match(sync, /--port1 993/);
  assert.match(sync, /--ssl1/);
  assert.match(sync, /--passfile1 \/run\/secrets\/wps_password/);
  assert.match(sync, /--passfile2 \/run\/secrets\/archive_password/);
  assert.doesNotMatch(sync, /--useuid/);
  assert.doesNotMatch(sync, /--delete1|--delete2|--expunge1|--expunge2/);
});

test("secret bootstrap prompts securely and writes NAS files with restrictive permissions", () => {
  const setSecrets = read("deploy/scripts/set-secrets.ps1");

  assert.match(setSecrets, /Read-Host .* -AsSecureString/);
  assert.match(setSecrets, /umask 077/);
  assert.match(setSecrets, /chmod 600/);
  assert.match(setSecrets, /ZeroFreeBSTR/);
  assert.doesNotMatch(setSecrets, /Start-Transcript/);
  assert.doesNotMatch(setSecrets, /brian\.lu@cimcwetrans\.com.*password/i);
});

test("deployment refuses to start sync without secrets", () => {
  const deploy = read("deploy/scripts/deploy.ps1");

  assert.match(deploy, /-SkipSync/);
  assert.match(deploy, /test -s .*wps_password/);
  assert.match(deploy, /test -s .*archive_password/);
  assert.match(deploy, /docker compose config/);
});

test("verification checks private access and avoids public mail listeners", () => {
  const verify = read("deploy/scripts/verify.ps1");

  assert.match(verify, /tailscale .*status/);
  assert.match(verify, /--socket=\/tmp\/tailscaled\.sock/);
  assert.match(verify, /Test-NetConnection/);
  assert.match(verify, /TailnetIp/);
  assert.match(verify, /openssl s_client/);
  assert.match(verify, /ss -ltnp/);
  assert.match(verify, /25\|465\|587/);
});
