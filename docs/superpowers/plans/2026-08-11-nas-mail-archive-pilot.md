# NAS Mail Archive Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a one-account NAS mail archive that copies WPS mail every 180 seconds, serves it to Foxmail through Tailscale IMAPS, and keeps outbound mail on WPS SMTPS.

**Architecture:** A Docker Compose project on the NAS runs Tailscale, Dovecot, and a lock-protected imapsync scheduler. WPS IMAP is the read-only synchronization source; Dovecot is the archive destination and Foxmail IMAP endpoint. Persistent mail data lives under `/data_n006/mail-archive`, while configuration, secrets, logs, and Tailscale state live under `/data_n006/apps/mail-archive`.

**Tech Stack:** Docker Compose, Tailscale, Dovecot, imapsync, POSIX shell, PowerShell, Node.js built-in test runner

## Global Constraints

- Account: `brian.lu@cimcwetrans.com`.
- Source IMAP: `mail.ksomail.com:993` with implicit TLS.
- Outbound SMTP: `mail.ksomail.com:465` with implicit TLS.
- Synchronization interval: exactly 180 seconds.
- Source synchronization is copy-only; never delete or expunge WPS messages.
- Do not expose NAS mail ports through the router or VPS.
- WPS and local archive credentials must be independent and must not enter Git or command-line arguments.
- Persistent message data must be stored below `/data_n006/mail-archive`.

---

## File Map

- `deploy/docker-compose.yml`: defines Tailscale, Dovecot, and imapsync scheduler services.
- `deploy/dovecot/dovecot.conf`: TLS-only Dovecot configuration and Maildir location.
- `deploy/sync/run-sync-loop.sh`: 180-second, non-overlapping imapsync loop with copy-only flags.
- `deploy/scripts/set-secrets.ps1`: interactively creates NAS-side WPS and archive secret files without printing values.
- `deploy/scripts/deploy.ps1`: copies the deployment bundle to the NAS and starts non-secret services.
- `deploy/scripts/verify.ps1`: verifies containers, Tailscale state, Dovecot TLS, scheduler logs, and source safety flags.
- `test/deployment-config.test.mjs`: static regression tests for interval, source safety, storage path, and public-port constraints.
- `docs/foxmail-setup.md`: exact Foxmail receive/send settings and local-cache guidance.

### Task 1: Deployment Configuration And Safety Tests

**Files:**
- Create: `test/deployment-config.test.mjs`
- Create: `deploy/docker-compose.yml`
- Create: `deploy/dovecot/dovecot.conf`

**Interfaces:**
- Consumes: Docker Engine 27 with Compose on `root@192.168.31.230:10000`.
- Produces: Compose services named `tailscale`, `dovecot`, and `mail-sync`; Dovecot endpoint `127.0.0.1:1993`; persistent Maildir `/data_n006/mail-archive/mail`.

- [ ] **Step 1: Write failing static configuration tests**

Create tests that parse Compose YAML as text and assert: `/data_n006/mail-archive` is mounted, Dovecot publishes only `127.0.0.1:1993:993`, no SMTP port is published, secrets are file mounts, and the sync service invokes `/app/run-sync-loop.sh`.

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const compose = fs.readFileSync("deploy/docker-compose.yml", "utf8");
const dovecot = fs.readFileSync("deploy/dovecot/dovecot.conf", "utf8");

test("mail data is persistent and IMAPS is loopback-only", () => {
  assert.match(compose, /\/data_n006\/mail-archive\/mail:\/srv\/mail/);
  assert.match(compose, /127\.0\.0\.1:1993:993/);
  assert.doesNotMatch(compose, /(?:^|[-\s'"])(?:25|465|587):/m);
});

test("credentials are mounted as files", () => {
  assert.match(compose, /wps_password:ro/);
  assert.match(compose, /archive_password:ro/);
  assert.doesNotMatch(compose, /WPS_PASSWORD\s*:/);
});

test("Dovecot requires TLS and stores Maildir on the persistent mount", () => {
  assert.match(dovecot, /ssl = required/);
  assert.match(dovecot, /mail_path = \/srv\/mail/);
  assert.match(dovecot, /auth_mechanisms = plain login/);
});
```

- [ ] **Step 2: Run tests and confirm missing files fail**

Run: `node --test test/deployment-config.test.mjs`

Expected: FAIL with `ENOENT` for `deploy/docker-compose.yml`.

- [ ] **Step 3: Add minimal Compose and Dovecot configuration**

Use named services with restart policies, persistent host mounts, read-only configuration mounts, loopback-only Dovecot publication, and no SMTP listener. Configure Dovecot for a single `archive` user whose password is read from `/run/secrets/archive_password`, Maildir at `/srv/mail`, and TLS certificate/key mounts at `/etc/dovecot/tls`.

- [ ] **Step 4: Run static tests**

Run: `node --test test/deployment-config.test.mjs`

Expected: all configuration tests PASS.

- [ ] **Step 5: Commit configuration**

```powershell
git add deploy/docker-compose.yml deploy/dovecot/dovecot.conf test/deployment-config.test.mjs
git commit -m "feat: add secure NAS mail services"
```

### Task 2: Copy-Only Three-Minute Synchronization

**Files:**
- Create: `deploy/sync/run-sync-loop.sh`
- Modify: `test/deployment-config.test.mjs`

**Interfaces:**
- Consumes: `/run/secrets/wps_password`, `/run/secrets/archive_password`, WPS IMAPS, and Dovecot IMAPS.
- Produces: one imapsync run immediately at startup and then at most one run per 180-second interval; logs under `/var/log/mail-sync`; no source deletion.

- [ ] **Step 1: Add failing scheduler safety tests**

```js
const sync = fs.readFileSync("deploy/sync/run-sync-loop.sh", "utf8");

test("scheduler runs every 180 seconds without overlap", () => {
  assert.match(sync, /sleep 180/);
  assert.match(sync, /flock -n/);
});

test("imapsync is copy-only and reads passwords from files", () => {
  assert.match(sync, /--host1 mail\.ksomail\.com/);
  assert.match(sync, /--port1 993/);
  assert.match(sync, /--ssl1/);
  assert.match(sync, /--password1 \/run\/secrets\/wps_password/);
  assert.match(sync, /--password2 \/run\/secrets\/archive_password/);
  assert.doesNotMatch(sync, /--delete1|--delete2|--expunge1|--expunge2/);
});
```

- [ ] **Step 2: Run tests and confirm missing script fails**

Run: `node --test test/deployment-config.test.mjs`

Expected: FAIL with `ENOENT` for `deploy/sync/run-sync-loop.sh`.

- [ ] **Step 3: Implement the synchronization loop**

The script must use `set -eu`, create a lock and log directory, invoke imapsync with `--host1 mail.ksomail.com --user1 brian.lu@cimcwetrans.com --passfile1 /run/secrets/wps_password --ssl1 --port1 993`, use local Dovecot as host 2 with the independent archive credential, preserve dates and flags, omit all deletion/expunge flags, log exit status, and sleep exactly 180 seconds. A non-blocking `flock` prevents overlap.

- [ ] **Step 4: Run tests and shell syntax check**

Run: `node --test test/deployment-config.test.mjs`

Run on NAS image: `docker run --rm -v "$PWD/deploy/sync:/app:ro" gilleslamiral/imapsync sh -n /app/run-sync-loop.sh`

Expected: tests PASS and shell syntax exits 0.

- [ ] **Step 5: Commit scheduler**

```powershell
git add deploy/sync/run-sync-loop.sh test/deployment-config.test.mjs
git commit -m "feat: synchronize WPS mail every three minutes"
```

### Task 3: Secure Deployment And Credential Bootstrap

**Files:**
- Create: `deploy/scripts/set-secrets.ps1`
- Create: `deploy/scripts/deploy.ps1`
- Modify: `test/deployment-config.test.mjs`

**Interfaces:**
- Consumes: interactive WPS authorization code and a new archive IMAP password; SSH target `root@192.168.31.230:10000`.
- Produces: root-readable NAS files `/data_n006/apps/mail-archive/secrets/wps_password` and `archive_password`, mode `0600`; deployment files under `/data_n006/apps/mail-archive/app`.

- [ ] **Step 1: Add failing secret-handling tests**

Assert that both scripts use `Read-Host -AsSecureString`, do not contain literal credential values, write remote secrets through standard input rather than command arguments, set mode `0600`, and never enable PowerShell transcript logging.

- [ ] **Step 2: Run tests and confirm missing scripts fail**

Run: `node --test test/deployment-config.test.mjs`

Expected: FAIL with `ENOENT` for the PowerShell scripts.

- [ ] **Step 3: Implement interactive secret bootstrap**

Prompt separately for the WPS app authorization code and a new archive password. Convert each secure string only long enough to stream UTF-8 bytes to `ssh ... "umask 077; cat > <path>"`; clear unmanaged BSTR memory in `finally`. Do not echo or persist values locally.

- [ ] **Step 4: Implement idempotent deployment script**

Create NAS directories with `0700` permissions, copy only version-controlled deployment files with `scp -P 10000`, validate Compose with `docker compose config`, and start Tailscale plus Dovecot before starting `mail-sync`. Refuse to start `mail-sync` until both secret files exist and are non-empty.

- [ ] **Step 5: Run tests and PowerShell parser checks**

Run: `node --test test/deployment-config.test.mjs`

Run: `Get-ChildItem deploy/scripts/*.ps1 | ForEach-Object { [void][scriptblock]::Create((Get-Content -Raw $_)) }`

Expected: all tests PASS and no parser exception.

- [ ] **Step 6: Commit deployment scripts**

```powershell
git add deploy/scripts test/deployment-config.test.mjs
git commit -m "feat: add secure NAS deployment workflow"
```

### Task 4: Deploy Tailscale And Obtain Private Connectivity

**Files:**
- Modify on NAS: `/data_n006/apps/mail-archive/app/docker-compose.yml`
- Create on NAS: `/data_n006/apps/mail-archive/tailscale/`

**Interfaces:**
- Consumes: user-approved Tailscale browser authorization.
- Produces: persistent NAS Tailnet membership, MagicDNS name, and Tailscale IPv4 address.

- [ ] **Step 1: Deploy configuration and pull images**

Run: `powershell -ExecutionPolicy Bypass -File deploy/scripts/deploy.ps1 -SkipSync`

Expected: Compose validates; Tailscale and Dovecot containers are created; `mail-sync` remains stopped.

- [ ] **Step 2: Start Tailscale authorization**

Run over SSH: `docker exec nas-mail-tailscale tailscale up --hostname nas-mail --accept-dns=false`

Expected: command prints a one-time `https://login.tailscale.com/a/...` URL without exposing any reusable credential.

- [ ] **Step 3: Complete browser authorization**

Open the URL, authorize `nas-mail`, then run: `docker exec nas-mail-tailscale tailscale status`.

Expected: status lists the NAS as connected and reports a `100.x.x.x` address.

- [ ] **Step 4: Install Tailscale on Windows and join the same Tailnet**

Use the official Windows installer, sign into the same Tailnet, and verify: `tailscale ping nas-mail`.

Expected: ping succeeds directly or through DERP.

### Task 5: TLS Certificate And IMAPS Exposure Through Tailscale

**Files:**
- Create on NAS: `/data_n006/apps/mail-archive/tls/dovecot.crt`
- Create on NAS: `/data_n006/apps/mail-archive/tls/dovecot.key`
- Modify: `deploy/scripts/verify.ps1`

**Interfaces:**
- Consumes: NAS Tailscale MagicDNS hostname and Tailscale certificate service.
- Produces: certificate-valid Dovecot IMAPS reachable from Tailnet peers on port 993 while the Docker host publication remains loopback-only.

- [ ] **Step 1: Add failing verification tests**

Test that `verify.ps1` checks the certificate hostname, `tailscale status`, loopback Dovecot TLS, Tailnet TCP reachability, and absence of public SMTP listeners.

- [ ] **Step 2: Generate a Tailscale certificate**

Run inside the Tailscale container using the actual MagicDNS name:

```sh
tailscale cert --cert-file /tls/dovecot.crt --key-file /tls/dovecot.key nas-mail.<tailnet>.ts.net
```

Expected: certificate and key are created; key mode is restricted.

- [ ] **Step 3: Configure Tailnet forwarding**

Use Tailscale TCP serve to forward Tailnet port 993 to host loopback port 1993 without exposing a router or VPS port:

```sh
tailscale serve --tcp=993 tcp://127.0.0.1:1993
```

Expected: `tailscale serve status` reports TCP 993 forwarding.

- [ ] **Step 4: Restart and verify Dovecot TLS**

Run: `docker compose restart dovecot`

Run from Windows: `Test-NetConnection nas-mail.<tailnet>.ts.net -Port 993`

Expected: TCP succeeds and the presented certificate matches the MagicDNS hostname.

### Task 6: Start Mail Synchronization And Verify Source Safety

**Files:**
- Create on NAS: secret files through `deploy/scripts/set-secrets.ps1`
- Modify on NAS: Docker service state only

**Interfaces:**
- Consumes: WPS authorization code entered interactively and archive password entered interactively.
- Produces: first complete WPS-to-NAS copy and subsequent attempts every 180 seconds.

- [ ] **Step 1: Create secret files interactively**

Run: `powershell -ExecutionPolicy Bypass -File deploy/scripts/set-secrets.ps1`

Expected: script reports only file creation and permissions, never credential values.

- [ ] **Step 2: Validate WPS login without logging the password**

Start a one-shot imapsync dry/login check using passfiles and verify successful authentication to both servers.

Expected: both IMAP logins succeed; no message is deleted or copied during the login-only check.

- [ ] **Step 3: Start scheduler**

Run on NAS: `docker compose up -d mail-sync`.

Expected: scheduler starts one sync immediately and reports a successful run in its logs.

- [ ] **Step 4: Verify three-minute behavior**

Observe timestamps for at least two starts in `docker logs nas-mail-sync`.

Expected: starts are at least 180 seconds apart and no overlapping imapsync process exists.

- [ ] **Step 5: Verify source remains intact**

Record WPS folder counts before and after synchronization and inspect imapsync options from the running container.

Expected: source counts do not decrease; command contains no delete or expunge option.

### Task 7: Foxmail Configuration And End-To-End Acceptance

**Files:**
- Create: `docs/foxmail-setup.md`

**Interfaces:**
- Consumes: NAS MagicDNS hostname, archive IMAP password, and existing WPS SMTP credential.
- Produces: Foxmail account that receives through NAS IMAPS and sends through WPS SMTPS with reduced local caching.

- [ ] **Step 1: Document exact account settings**

Document incoming server `nas-mail.<tailnet>.ts.net`, port `993`, SSL/TLS, username `archive`; outgoing server `mail.ksomail.com`, port `465`, SSL/TLS, username `brian.lu@cimcwetrans.com`. Explain how to disable full-body/attachment offline download where supported.

- [ ] **Step 2: Add the account in Foxmail**

Use manual setup so incoming NAS credentials and outgoing WPS credentials can differ.

Expected: folder list loads from Dovecot and no certificate warning appears.

- [ ] **Step 3: Validate incoming synchronization**

Send a test message to WPS and wait up to two scheduler cycles.

Expected: the message appears in Foxmail within approximately six minutes, with Chinese subject, date, body, and attachment intact.

- [ ] **Step 4: Validate reply and sent copy**

Reply through WPS SMTPS and confirm delivery. Confirm that WPS Sent is copied back to NAS on a later synchronization cycle and is visible through Dovecot.

Expected: reply is delivered and its sent copy becomes visible in the NAS-backed account.

- [ ] **Step 5: Run final verification and document rollback**

Run: `powershell -ExecutionPolicy Bypass -File deploy/scripts/verify.ps1`

Expected: all checks PASS. Record rollback as `docker compose stop mail-sync dovecot tailscale`; do not remove `/data_n006/mail-archive` or the app state directory.

- [ ] **Step 6: Commit operational documentation**

```powershell
git add deploy/scripts/verify.ps1 docs/foxmail-setup.md
git commit -m "docs: add Foxmail setup and mail pilot verification"
```
