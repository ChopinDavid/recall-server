# recall-server setup for Windows - puts a personal Anki sync server on this computer.
#
#   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/ChopinDavid/recall-server/main/setup-server.ps1 | iex"
#
# Works from Command Prompt or PowerShell. What it does, in order:
#   1. Downloads the anki-sync-server binary for this machine (from this
#      repo's GitHub Releases; built by CI from ankitects/anki, AGPL-3.0).
#   2. Asks for a username/password, defaulting to your login name and a
#      random password (or keeps your existing ones).
#   3. Allows the server through Windows Firewall on private networks (one
#      administrator prompt), so your phone can reach it.
#   4. Registers a Scheduled Task so the server starts at login and restarts
#      if it stops.
#   5. Prints the address + credentials to enter in Recall and Anki desktop.
#
# Re-running is safe: it upgrades the binary and keeps credentials + data.
# Data lives in %USERPROFILE%\.recall-server\data - back it up like any Anki data.
#
# Everything runs inside one script block so an error stops the setup without
# closing a PowerShell window it was pasted into.
& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Windows PowerShell's progress bar slows downloads badly
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo     = 'ChopinDavid/recall-server'
$HomeDir  = Join-Path $env:USERPROFILE '.recall-server'
$Bin      = Join-Path $HomeDir 'anki-sync-server.exe'
$EnvFile  = Join-Path $HomeDir 'server-env'
$DataDir  = Join-Path $HomeDir 'data'
$LogFile  = Join-Path $HomeDir 'server.log'
$Runner   = Join-Path $HomeDir 'run-server.ps1'
$TaskName = 'recall-anki-sync-server'
$RuleName = 'recall-server (Anki sync)'
$Port     = if ($env:RECALL_SERVER_PORT) { $env:RECALL_SERVER_PORT } else { '8080' }

function Say([string]$m) { Write-Host $m }
function Fail([string]$m) { throw "setup-server: $m" }

try {
  if ($Port -notmatch '^\d+$' -or [int]$Port -lt 1 -or [int]$Port -gt 65535) { Fail "RECALL_SERVER_PORT must be a number from 1 to 65535." }

  # ---- 1. platform + latest release asset ---------------------------------
  $Arch = $null
  try { $Arch = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" } catch { }
  if (-not $Arch) { $Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }
  switch -Regex ($Arch) {
    '^(X64|AMD64)$' { $Asset = 'anki-sync-server-windows-x86_64.exe' }
    '^(Arm64|ARM64)$' { $Asset = 'anki-sync-server-windows-arm64.exe' }
    default { Fail "no prebuilt binary for Windows/$Arch yet." }
  }

  New-Item -ItemType Directory -Force -Path $HomeDir, $DataDir | Out-Null

  # A running server locks its .exe, so stop it (and its restart loop) first.
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Runner) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-Process -Name 'anki-sync-server' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $Bin } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500

  Say "Downloading the sync server ($Asset)..."
  $Url = "https://github.com/$Repo/releases/latest/download/$Asset"
  try { Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile "$Bin.tmp" } catch { Fail "download failed: $Url" }
  Move-Item -Force "$Bin.tmp" $Bin

  # ---- 2. credentials (kept across re-runs) -------------------------------
  # With no console to ask in (CI, provisioning), defaults or
  # RECALL_SERVER_USER / RECALL_SERVER_PASSWORD are used without asking.
  # The server reads SYNC_USER1 as user:password and keeps each user's data in
  # a folder named after them, so the name must be a valid folder name and
  # can't contain ':'.
  $BadUserChars = '[\\/:*?"<>|]'
  function Test-BadUser([string]$u) { return (-not $u) -or ($u -match $BadUserChars) -or ($u.Trim() -ne $u) }
  function Read-Secret([string]$prompt) {
    $s = Read-Host -AsSecureString -Prompt $prompt
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
  }
  $Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

  if (Test-Path -LiteralPath $EnvFile) {
    Say "Keeping your existing username/password."
  } else {
    $DefaultUser = if ($env:USERNAME) { $env:USERNAME } else { 'anki' }
    $UserName = $env:RECALL_SERVER_USER
    $Pass = $env:RECALL_SERVER_PASSWORD
    if ($UserName) {
      if (Test-BadUser $UserName) { Fail "RECALL_SERVER_USER can't contain \ / : * ? `" < > | or start/end with a space." }
    } elseif ($Interactive) {
      while ($true) {
        $UserName = Read-Host -Prompt "Username [$DefaultUser]"
        if (-not $UserName) { $UserName = $DefaultUser }
        if (-not (Test-BadUser $UserName)) { break }
        Say "  A username can't contain \ / : * ? `" < > | or start/end with a space."
      }
    } else {
      $UserName = $DefaultUser
    }
    if (-not $Pass -and -not $env:RECALL_SERVER_USER -and $Interactive) {
      while ($true) {
        $Pass = Read-Secret 'Password (Enter for a random one)'
        if (-not $Pass) { break }
        if ((Read-Secret 'Confirm password') -ceq $Pass) { break }
        Say "  Those didn't match; try again."
      }
    }
    if (-not $Pass) {
      $chars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      $bytes = New-Object byte[] 16
      [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      $Pass = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    }
    # Plain KEY=VALUE lines; run-server.ps1 splits each at the first '=', so
    # any password survives. The folder inherits your profile's private ACL.
    [IO.File]::WriteAllLines($EnvFile, [string[]]@(
      "SYNC_USER1=${UserName}:${Pass}",
      "SYNC_BASE=$DataDir",
      "SYNC_HOST=0.0.0.0",
      "SYNC_PORT=$Port"
    ))
  }
  $Settings = @{}
  foreach ($line in [IO.File]::ReadAllLines($EnvFile)) {
    $i = $line.IndexOf('=')
    if ($i -gt 0) { $Settings[$line.Substring(0, $i)] = $line.Substring($i + 1) }
  }
  $Port = $Settings['SYNC_PORT']
  $CredsUser = $Settings['SYNC_USER1'].Split(':', 2)[0]
  $CredsPass = $Settings['SYNC_USER1'].Split(':', 2)[1]

  # ---- 3. firewall: let the phone reach the server -------------------------
  # Scoped to this program, this port and Private networks. Adding a rule
  # needs administrator rights, hence one UAC prompt (skipped when it exists).
  $FwCommand = "Get-NetFirewallRule -DisplayName '$RuleName' -ErrorAction SilentlyContinue | Remove-NetFirewallRule; " +
    "New-NetFirewallRule -DisplayName '$RuleName' -Direction Inbound -Action Allow -Protocol TCP " +
    "-LocalPort $Port -Program '$($Bin.Replace("'", "''"))' -Profile Private | Out-Null"
  $FwOk = $false
  try {
    $rule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rule) {
      $ports = ($rule | Get-NetFirewallPortFilter).LocalPort
      $prog = ($rule | Get-NetFirewallApplicationFilter).Program
      $FwOk = ($rule.Enabled -eq 'True') -and ("$ports" -eq "$Port") -and ($prog -eq $Bin)
    }
  } catch { }
  if (-not $FwOk) {
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    try {
      if ($IsAdmin) {
        Invoke-Expression $FwCommand
      } else {
        Say "Windows will ask for permission to let your phone reach the server..."
        $Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($FwCommand))
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden `
          -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $Encoded"
        if ($p.ExitCode -ne 0) { throw "exit $($p.ExitCode)" }
      }
      $FwOk = $true
    } catch { $FwOk = $false }
  }

  # ---- 4. run at login, restart on crash -----------------------------------
  # run-server.ps1 loads server-env into its own environment and keeps the
  # server running; cmd appends the server's output to server.log.
  [IO.File]::WriteAllLines($Runner, [string[]]@(
    '# Started at login by the recall-anki-sync-server Scheduled Task.',
    'foreach ($line in [IO.File]::ReadAllLines((Join-Path $PSScriptRoot ''server-env''))) {',
    '  $i = $line.IndexOf(''='')',
    '  if ($i -gt 0) { [Environment]::SetEnvironmentVariable($line.Substring(0, $i), $line.Substring($i + 1), ''Process'') }',
    '}',
    '$env:RS_BIN = Join-Path $PSScriptRoot ''anki-sync-server.exe''',
    '$env:RS_LOG = Join-Path $PSScriptRoot ''server.log''',
    'while ($true) {',
    '  Start-Process -FilePath cmd.exe -ArgumentList ''/d /c ""%RS_BIN%" >> "%RS_LOG%" 2>&1"'' -NoNewWindow -Wait',
    '  Start-Sleep -Seconds 5',
    '}'
  ))

  $Me = "$env:USERDOMAIN\$env:USERNAME"
  $Action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Runner`""
  $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $Me
  $Principal = New-ScheduledTaskPrincipal -UserId $Me -LogonType Interactive -RunLevel Limited
  $TaskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal `
    -Settings $TaskSettings -Description 'Personal Anki sync server (recall-server)' -Force | Out-Null
  Start-ScheduledTask -TaskName $TaskName

  # ---- 5. verify + print the card ------------------------------------------
  # The address the PHONE should use: the interface carrying the default route.
  $Addr = $null; $Category = $null
  try {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
      Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
    $Addr = (Get-NetIPAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4 -ErrorAction Stop |
      Select-Object -First 1).IPAddress
    $Category = "$((Get-NetConnectionProfile -InterfaceIndex $route.ifIndex -ErrorAction Stop).NetworkCategory)"
  } catch { }
  if (-not $Addr) { $Addr = "<your computer's local address>" }

  # Give it up to ~10s; any HTTP answer (even 404) means it's serving.
  $Running = $false
  for ($n = 0; $n -lt 10 -and -not $Running; $n++) {
    try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri "http://127.0.0.1:$Port/" | Out-Null; $Running = $true }
    catch { if ($_.Exception.Response) { $Running = $true } else { Start-Sleep -Seconds 1 } }
  }

  Say ""
  Say "==============================================================="
  Say " Your Anki sync server is set up."
  Say ""
  Say "   In Recall on your phone:"
  Say "     Sync endpoint:  http://${Addr}:$Port/"
  Say "     Username:       $CredsUser"
  Say "     Password:       $CredsPass"
  Say ""
  Say "   In Anki on this computer (Tools -> Preferences -> Syncing):"
  Say "     Self-hosted sync server:  http://localhost:$Port/"
  Say "     Then restart Anki, press Sync, and choose Upload."
  Say ""
  Say "   It starts automatically when you log in."
  Say "   Data: $DataDir"
  Say "   Log:  $LogFile"
  if (-not $Running) { Say "   NOTE: the server has not answered yet; check the log above." }
  if (-not $FwOk) {
    Say ""
    Say "   NOTE: Windows Firewall wasn't updated, so your phone may not reach"
    Say "   the server. To allow it, run this in PowerShell as administrator:"
    Say "     $FwCommand"
  }
  if ($Category -eq 'Public') {
    Say ""
    Say "   NOTE: Windows treats this network as Public, which blocks your phone."
    Say "   In Settings -> Network & internet, open this network and choose Private."
  }
  Say "==============================================================="
} catch {
  Write-Host ""
  Write-Host $_.Exception.Message -ForegroundColor Red
}
}
