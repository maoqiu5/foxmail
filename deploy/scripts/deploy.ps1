param(
  [switch]$SkipSync,
  [string]$NasTarget = "root@192.168.31.230",
  [int]$NasPort = 10000,
  [string]$SshKey = "$HOME\.ssh\cnstock_vps",
  [string]$KnownHosts = "C:\Users\12514\Documents\ChatGPT\foxmail\.nas_known_hosts",
  [string]$RemoteRoot = "/data_n006/apps/mail-archive"
)

$ErrorActionPreference = "Stop"

# Usage for first-stage deployment: powershell -ExecutionPolicy Bypass -File deploy/scripts/deploy.ps1 -SkipSync

$localDeploy = Resolve-Path (Join-Path $PSScriptRoot "..")
$remoteApp = "$RemoteRoot/app"

function Invoke-NasSsh {
  param([string]$Command)

  & ssh -i $SshKey -p $NasPort `
    -o BatchMode=yes `
    -o ConnectTimeout=8 `
    -o StrictHostKeyChecking=accept-new `
    -o "UserKnownHostsFile=$KnownHosts" `
    $NasTarget $Command
  if ($LASTEXITCODE -ne 0) {
    throw "NAS SSH command failed with exit code $LASTEXITCODE"
  }
}

Invoke-NasSsh "umask 077; mkdir -p '$remoteApp' '$RemoteRoot/secrets' '$RemoteRoot/tailscale' '$RemoteRoot/tls' '$RemoteRoot/logs' '/data_n006/mail-archive/mail'"

& scp -i $SshKey -P $NasPort `
  -o StrictHostKeyChecking=accept-new `
  -o "UserKnownHostsFile=$KnownHosts" `
  "$localDeploy\docker-compose.yml" `
  "${NasTarget}:$remoteApp/docker-compose.yml"

& scp -i $SshKey -P $NasPort -r `
  -o StrictHostKeyChecking=accept-new `
  -o "UserKnownHostsFile=$KnownHosts" `
  "$localDeploy\dovecot" `
  "$localDeploy\sync" `
  "${NasTarget}:$remoteApp/"

Invoke-NasSsh "cd '$remoteApp' && docker compose config >/dev/null"
Invoke-NasSsh "cd '$remoteApp' && docker compose up -d --build tailscale"

if ($SkipSync) {
  Write-Host "Tailscale service deployed. Skipping Dovecot and mail-sync startup."
  exit 0
}

Invoke-NasSsh "test -s '$RemoteRoot/secrets/wps_password' && test -s '$RemoteRoot/secrets/archive_password'"
Invoke-NasSsh "test -s '$RemoteRoot/tls/dovecot.crt' && test -s '$RemoteRoot/tls/dovecot.key'"
Invoke-NasSsh "cd '$remoteApp' && docker compose up -d --build dovecot mail-sync"

Write-Host "NAS mail archive deployment started."
