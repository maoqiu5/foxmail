param(
  [string]$NasTarget = "root@192.168.31.230",
  [int]$NasPort = 10000,
  [string]$SshKey = "$HOME\.ssh\cnstock_vps",
  [string]$KnownHosts = "C:\Users\12514\Documents\ChatGPT\foxmail\.nas_known_hosts",
  [string]$RemoteRoot = "/data_n006/apps/mail-archive",
  [string]$TailnetHost = "nas-mail.tail5e6b.ts.net",
  [string]$TailnetIp = "100.122.207.88"
)

$ErrorActionPreference = "Stop"

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

Write-Host "Checking NAS mail containers..."
Invoke-NasSsh "cd '$RemoteRoot/app' && docker compose ps"

Write-Host "Checking Tailscale status..."
Invoke-NasSsh "docker exec nas-mail-tailscale tailscale --socket=/tmp/tailscaled.sock status"

Write-Host "Checking local Dovecot TLS inside Tailnet network namespace..."
Invoke-NasSsh "docker exec nas-mail-dovecot sh -c 'echo | openssl s_client -connect 127.0.0.1:993 -servername $TailnetHost 2>/dev/null | grep -E BEGIN\|Verify'"

Write-Host "Checking Windows Tailnet TCP reachability..."
$tcpOk = Test-NetConnection $TailnetHost -Port 993 -InformationLevel Quiet
if (-not $tcpOk) {
  Write-Host "Primary Tailnet host '$TailnetHost' is not reachable; trying Tailscale IP '$TailnetIp'..."
  $tcpOk = Test-NetConnection $TailnetIp -Port 993 -InformationLevel Quiet
}
if (-not $tcpOk) {
  throw "Cannot reach $TailnetHost (or $TailnetIp) port 993 from Windows"
}

Write-Host "Checking no public SMTP listener is configured on NAS..."
Invoke-NasSsh "ss -ltnp 2>/dev/null | grep -E ':(25|465|587)\b' && exit 1 || exit 0"

Write-Host "Checking recent synchronization logs..."
Invoke-NasSsh "tail -30 '$RemoteRoot/logs/latest-minute-runner.log' 2>/dev/null || true; echo '--- sent-sync ---'; tail -30 '$RemoteRoot/logs/sent-sync-runner.log' 2>/dev/null || true"

Write-Host "Verification completed."
