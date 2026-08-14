# Foxmail Setup For NAS Mail Archive

## Incoming Mail

- Protocol: IMAP
- Server: `100.122.207.88`
- MagicDNS alternative: `nas-mail.tail5e6b.ts.net`
- Port: `993`
- Encryption: SSL/TLS
- Username: `brian.lu@cimcwetrans.com`
- Password: WPS mailbox password or application authorization code

This Foxmail version uses one username and password for both incoming and outgoing servers. Dovecot therefore accepts the WPS mailbox credential for this account and maps it to the NAS archive Maildir. The independent `archive` account remains available for clients that support separate credentials.

The pilot currently uses a self-signed Dovecot certificate because this Tailscale account does not support Tailscale-managed TLS certificates. If Foxmail warns about the certificate, verify that the server is `100.122.207.88` or `nas-mail.tail5e6b.ts.net` before accepting it for this account.

## Outgoing Mail

- Protocol: SMTP
- Server: `mail.ksomail.com`
- Port: `465`
- Encryption: SSL/TLS
- Username: `brian.lu@cimcwetrans.com`
- Password: WPS mailbox password or application authorization code

## Local Space Reduction

In Foxmail, reduce or disable full offline download for this NAS-backed account where the client allows it. Prefer headers and recent-message cache over full body and attachment cache. Keep the original WPS account disabled, removed, or configured with limited retention after the NAS archive is verified.

## Verification

1. Confirm the folder list loads from `100.122.207.88`.
2. Send a test message to `brian.lu@cimcwetrans.com`.
3. Wait up to two scheduler cycles, about six minutes.
4. Confirm the message appears with subject, body, date, and attachment intact.
5. Reply from Foxmail through WPS SMTP.
6. Confirm the reply is delivered and later appears in the NAS-backed Sent folder after synchronization.
