# NAS Mail Archive Pilot Design

## Goal

Move the bulk of `brian.lu@cimcwetrans.com` mail storage from the Windows PC to the NAS while preserving remote reading and replying. The pilot must not require a public IP and must not turn the NAS into a public SMTP server.

## Scope

- One WPS Mail account: `brian.lu@cimcwetrans.com`.
- Source IMAP: `mail.ksomail.com:993` with implicit TLS.
- Outbound SMTP remains WPS Mail: `mail.ksomail.com:465` with implicit TLS.
- Source mail is synchronized to NAS storage every three minutes.
- Dovecot exposes the NAS copy over IMAPS inside a Tailscale private network.
- Foxmail reads the NAS copy through Tailscale and sends replies through WPS SMTP.
- Initial synchronization is copy-only: no source messages are deleted or expunged by the NAS.

## Architecture

```text
WPS IMAPS (993)
        |
        | every 3 minutes
        v
NAS sync service -> Maildir at /data_n006/mail-archive
                              |
                              v
                      Dovecot IMAPS
                              |
                      Tailscale network
                              |
                              v
                           Foxmail

Foxmail replies -> WPS SMTPS (465)
```

The NAS does not accept public SMTP traffic. IMAPS is reachable only from the LAN and the Tailscale interface; no router port forwarding or VPS TCP tunnel is required.

## Components

### Tailscale

Tailscale runs on the NAS using a persistent state directory and access to `/dev/net/tun`. The Windows PC joins the same Tailnet. An interactive Tailscale authorization step is expected during deployment.

### Mail Synchronization

A dedicated container synchronizes WPS IMAP folders into the NAS Maildir every three minutes. The scheduler prevents overlapping runs, records success and failure logs, and never deletes messages from WPS during the pilot.

The WPS password or application authorization code is stored in a NAS-side secret file with restrictive permissions. It is excluded from Git, logs, Compose environment output, and this design document.

### Dovecot

Dovecot serves the Maildir through IMAPS. It uses a separate local IMAP username and password rather than reusing the WPS credential. Plain IMAP authentication is allowed only inside TLS.

### Foxmail

Foxmail receives mail from the NAS Dovecot endpoint over Tailscale. Sending continues to use `mail.ksomail.com:465`. Local offline download and attachment caching should be reduced or disabled so that the PC remains a thin client.

## Storage And Backup

Pilot data is stored below `/data_n006/mail-archive`, which currently has substantially more free space than the other NAS data volumes. Container configuration and Tailscale state are stored separately from message data.

Before the pilot is treated as the primary archive, the Maildir and configuration must be covered by a NAS snapshot or versioned backup. Synchronization alone is not a backup because deletions or corruption can eventually propagate.

## Security Boundaries

- Do not expose ports 993, 465, 587, or 25 through the router or public VPS.
- Require TLS for IMAP authentication.
- Use independent credentials for WPS synchronization and NAS IMAP access.
- Mount credential files read-only where possible and restrict host file permissions.
- Keep source deletion disabled throughout the pilot.
- Limit service access to LAN and Tailscale paths.

## Failure Handling

- A failed WPS synchronization leaves the last successful NAS copy available.
- The next three-minute interval retries automatically.
- A lock prevents a slow run from overlapping the next run.
- Loss of Tailscale affects remote access but does not stop NAS synchronization.
- Loss of WPS connectivity affects synchronization but does not stop access to already archived messages.
- Deployment can be rolled back by stopping and removing the pilot containers while retaining `/data_n006/mail-archive`.

## Verification

The pilot is accepted when all of the following pass:

1. The NAS joins the Tailnet and is reachable from the Windows PC over its Tailscale address.
2. Dovecot accepts an encrypted IMAP login through Tailscale.
3. A test WPS folder and messages appear in the NAS Maildir and in Foxmail.
4. A new WPS message appears in the NAS-backed Foxmail account within two scheduler cycles, allowing reasonable server delay.
5. Chinese subjects, folder names, attachments, dates, and read state are preserved sufficiently for normal use.
6. Foxmail can send a reply through WPS SMTPS and retain an accessible sent copy.
7. Stopping the synchronization container does not delete or alter messages in WPS Mail.

## Deferred Work

- Public SMTP reception or delivery from the NAS.
- Public exposure of IMAP through the VPS.
- Automatic deletion from WPS after archival.
- Multiple accounts.
- Full Webmail deployment.
- Treating the NAS archive as the sole backup before snapshots are configured.
