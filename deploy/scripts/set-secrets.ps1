param(
  [string]$NasTarget = "root@192.168.31.230",
  [int]$NasPort = 10000,
  [string]$SshKey = "$HOME\.ssh\cnstock_vps",
  [string]$KnownHosts = "C:\Users\12514\Documents\ChatGPT\foxmail\.nas_known_hosts",
  [string]$RemoteRoot = "/data_n006/apps/mail-archive"
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
}

function SecureStringToPlainText {
  param([securestring]$SecureValue)

  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
  try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Quote-ProcessArgument {
  param([string]$Value)

  if ($Value -notmatch '[\s"]') {
    return $Value
  }

  return '"' + ($Value -replace '\\(?=\\*")', '$0$0' -replace '"', '\"') + '"'
}

function Write-RemoteSecret {
  param(
    [string]$Name,
    [securestring]$Value
  )

  $remotePath = "$RemoteRoot/secrets/$Name"
  $plain = SecureStringToPlainText $Value
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($plain)
    $command = "umask 077; mkdir -p '$RemoteRoot/secrets'; cat > '$remotePath'; chmod 600 '$remotePath'; test -s '$remotePath'"
    $args = @(
      "-i", $SshKey,
      "-p", "$NasPort",
      "-o", "BatchMode=yes",
      "-o", "ConnectTimeout=8",
      "-o", "StrictHostKeyChecking=accept-new",
      "-o", "UserKnownHostsFile=$KnownHosts",
      $NasTarget,
      $command
    )
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = "ssh"
    $psi.Arguments = ($args | ForEach-Object { Quote-ProcessArgument $_ }) -join " "
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($psi)
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.Close()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
      throw "Failed to write remote secret $Name"
    }
  } finally {
    $plain = $null
    [GC]::Collect()
  }
}

$wpsPassword = Read-Host "Enter WPS IMAP authorization code" -AsSecureString
$archivePassword = Read-Host "Enter new NAS archive IMAP password" -AsSecureString

Invoke-NasSsh "umask 077; mkdir -p '$RemoteRoot/secrets'"
Write-RemoteSecret -Name "wps_password" -Value $wpsPassword
Write-RemoteSecret -Name "archive_password" -Value $archivePassword
Invoke-NasSsh "chmod 600 '$RemoteRoot/secrets/wps_password' '$RemoteRoot/secrets/archive_password'; ls -l '$RemoteRoot/secrets'"

Write-Host "NAS mail archive secrets created with mode 0600."
