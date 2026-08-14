#!/bin/sh
set -eu

if [ ! -s /run/secrets/archive_password ]; then
  echo "archive_password secret is missing or empty" >&2
  exit 1
fi

if [ ! -s /run/secrets/wps_password ]; then
  echo "wps_password secret is missing or empty" >&2
  exit 1
fi

if [ ! -s /etc/dovecot/tls/dovecot.crt ] || [ ! -s /etc/dovecot/tls/dovecot.key ]; then
  echo "Dovecot TLS certificate or key is missing" >&2
  exit 1
fi

addgroup -S vmail 2>/dev/null || true
adduser -S -D -H -G vmail -s /sbin/nologin vmail 2>/dev/null || true

mkdir -p \
  /srv/mail/archive/Maildir/cur \
  /srv/mail/archive/Maildir/new \
  /srv/mail/archive/Maildir/tmp \
  /run/dovecot
chown vmail:vmail /srv/mail
chmod 0750 /srv/mail
chown -R vmail:vmail /srv/mail/archive /run/dovecot
chmod 0700 /srv/mail/archive

archive_password=$(cat /run/secrets/archive_password)
wps_password=$(cat /run/secrets/wps_password)
vmail_uid=$(id -u vmail)
vmail_gid=$(id -g vmail)
{
  printf 'archive:{PLAIN}%s:%s:%s::/srv/mail/archive::userdb_mail_driver=maildir userdb_mail_path=/srv/mail/archive/Maildir\n' "$archive_password" "$vmail_uid" "$vmail_gid"
  printf 'brian.lu@cimcwetrans.com:{PLAIN}%s:%s:%s::/srv/mail/archive::userdb_mail_driver=maildir userdb_mail_path=/srv/mail/archive/Maildir\n' "$wps_password" "$vmail_uid" "$vmail_gid"
} > /run/dovecot/users
chown dovecot:dovecot /run/dovecot/users
chmod 0640 /run/dovecot/users

exec dovecot -F
