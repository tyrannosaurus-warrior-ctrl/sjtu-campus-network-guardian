#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramData 'SJTU-Network-Mode'
$app = Join-Path $root 'GuardianApp'
$configPath = Join-Path $root 'guardian-config.json'
$knownCampusDns = @('202.120.2.101','202.120.2.100','202.112.26.40','2001:da8:8000:6180:150:112:26:40','2001:da8:8000:1:202:120:2:101')

function Get-DnsFor([int]$Index) {
    @(Get-DnsClientServerAddress -InterfaceIndex $Index -ErrorAction SilentlyContinue |
        ForEach-Object ServerAddresses | Where-Object { $_ -and $_ -notlike 'fec0:*' })
}
function Save-Json($Path, $Value) {
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $root, $app | Out-Null

# A pre-existing config means an upgrade. Keep its baseline: it is the only safe
# record of the user's DNS before Guardian was installed.
if (-not (Test-Path $configPath)) {
    $baselines = @()
    foreach ($adapter in @(Get-NetAdapter -IncludeHidden | Where-Object HardwareInterface)) {
        # A public installer must never silently enroll a home Ethernet/Wi-Fi
        # adapter. Unknown/static campus adapters are added later from the UI.
        if (@(Get-DnsFor $adapter.ifIndex | Where-Object { $_ -in $knownCampusDns }).Count -eq 0) { continue }
        $id = ([guid]$adapter.InterfaceGuid).ToString('D')
        $key4 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{$id}"
        $key6 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\{$id}"
        $static4 = (Get-ItemProperty -Path $key4 -Name NameServer -ErrorAction SilentlyContinue).NameServer
        $static6 = (Get-ItemProperty -Path $key6 -Name NameServer -ErrorAction SilentlyContinue).NameServer
        $baselines += [ordered]@{
            interfaceGuid = $adapter.InterfaceGuid.ToString(); alias = $adapter.Name
            mode = if ([string]::IsNullOrWhiteSpace($static4) -and [string]::IsNullOrWhiteSpace($static6)) { 'dhcp' } else { 'static' }
            addresses = @(Get-DnsFor $adapter.ifIndex); captured = (Get-Date).ToString('o')
        }
    }
    $doh = @(Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue | ForEach-Object {
        @{ address=$_.ServerAddress; template=$_.DohTemplate; autoUpgrade=[bool]$_.AutoUpgrade; fallback=[bool]$_.AllowFallbackToUdp }
    })
    Save-Json $configPath ([ordered]@{ version=2; enabled=$false; installed=(Get-Date).ToString('o'); baselines=$baselines; dohOriginal=$doh })
}

foreach ($file in 'Set-GuardianProtection.ps1','Capture-GuardianDns.ps1','Uninstall-Guardian.ps1','Grant-GuardianTaskRun.ps1','SjtuGuardian.exe') {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path $source)) { throw "Installation package is incomplete: $file" }
    $destination = if ($file -eq 'SjtuGuardian.exe') { Join-Path $app $file } else { Join-Path $root $file }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps)) { throw 'Windows PowerShell 5.1 is required to run Guardian scheduled tasks.' }
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Highest
foreach ($actionName in 'Enable','Disable','Check','Snapshot','Enroll') {
    $action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $root 'Set-GuardianProtection.ps1')`" -Action $actionName"
    $task = if ($actionName -eq 'Check') {
        New-ScheduledTask -Action $action -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $identity) -Settings $settings -Principal $principal
    } else { New-ScheduledTask -Action $action -Settings $settings -Principal $principal }
    Register-ScheduledTask -TaskName "SJTU Guardian - $actionName" -InputObject $task -Force | Out-Null
}
$captureAction = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $root 'Capture-GuardianDns.ps1')`""
Register-ScheduledTask -TaskName 'SJTU Guardian - Capture' -InputObject (New-ScheduledTask -Action $captureAction -Settings $settings -Principal $principal) -Force | Out-Null
& (Join-Path $root 'Grant-GuardianTaskRun.ps1')

$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
# Build the Chinese shortcut name from Unicode code points so Windows PowerShell 5.1
# can read this UTF-8 file safely even when it has no BOM.
$shortcutName = (-join @([char]0x6821, [char]0x56ED, [char]0x7F51, [char]0x7EDC, [char]0x7BA1, [char]0x5BB6)) + '.lnk'
$link = $shell.CreateShortcut((Join-Path $desktop $shortcutName))
$link.TargetPath = Join-Path $app 'SjtuGuardian.exe'; $link.WorkingDirectory = $app; $link.Save()
& (Join-Path $root 'Set-GuardianProtection.ps1') -Action Snapshot
Write-Host 'Installed. Protection is OFF by default. Open 校园网网络管家 and confirm the campus adapter before enabling it.'
