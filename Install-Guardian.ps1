github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/blob/main/Install-Guardian.ps1#start-of-content
		4 container Global navigation menu
			5 pop up button Open menu
			6 link Description: Homepage ( g then d ), Value: github.com/
			7 container Breadcrumbs
				8 content list
					9 button (collapsed) Secondary Actions: Expand
					10 container
						11 link Description: sjtu-campus-network-guardian, Value: github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian
						12 pop up button (collapsed) Switch repository ( alt shift r ), Secondary Actions: Expand
			13 button Open quick search dialog, type / to search ( forward slash )
			14 link Description: You have no unread notifications ( g then n ), Value: github.com/notifications
			15 pop up button Open user navigation menu
				16 image tyrannosaurus warrior
			17 heading Repository navigation, Value: 2
				18 text Repository navigation
			19 container Repository
				20 content list
					21 link Description: Code, Value: github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian
					22 link Description: Issues, Value: github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/issues
					23 link Description: Pull requests  (3), Value: github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/pulls
					24 link Description: Actions, Value: github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/actions
				25 pop up button (collapsed) More items, Secondary Actions: Expand
	26 container
		27 container repos-split-pane-content
			28 container StickyHeader
				29 heading Expand file tree, Value: 2
					30 button Expand file tree
				31 pop up button (collapsed) Description: main branch, ID: ref-picker-repos-header-ref-selector-wide, Secondary Actions: Expand
					32 text main
				33 container Breadcrumbs, ID: repos-header-breadcrumb
					34 heading Breadcrumbs, Value: 2, ID: repos-header-breadcrumb-heading
						35 text Breadcrumbs
					36 content list
						37 link Description: sjtu-campus-network-guardian, Value: github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/tree/main
				38 heading Install-Guardian.ps1, Value: 1, ID: file-name-id
					39 text Install-Guardian.ps1
				40 button Copy path
				41 pop up button (collapsed) More file actions, Secondary Actions: Expand
			42 heading Latest commit, Value: 2
				43 text Latest commit
			44 image author
			45 text SJTU Network Guardian Contributors
			46 container Sep 15, 2026, 16:23 GMT+8
				47 text yesterday
			48 heading History, Value: 2
				49 text History
			50 checkbox (collapsed) Open commit details, Value: 0, Secondary Actions: Expand
			51 link Description: View commit history for this file., Value: github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/commits/main/Install-Guardian.ps1
			52 text 72 lines (66 loc) · 4.77 KB
			53 container
				54 heading File metadata and controls, Value: 2
					55 text File metadata and controls
				56 content list File view
					57 checkbox Code, Value: 1
						58 text Code
					59 checkbox Blame, Value: 0
						60 text Blame
				61 checkbox (collapsed) Open symbols panel, Value: 0, ID: symbols-button, Secondary Actions: Expand
				62 pop up button (collapsed) Edit and raw actions, Help: More file actions, Secondary Actions: Expand
			63 container highlighted-line-menu-positioner
				64 container copilot-button-positioner
					65 container
						66 text entry area Description: file content, ID: read-only-cursor-text-area, Value: #Requires -RunAsAdministrator
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
