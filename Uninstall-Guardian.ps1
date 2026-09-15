#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'SJTU-Network-Mode'
$configPath=Join-Path $root 'guardian-config.json'
if (-not (Test-Path $configPath)) { throw 'Guardian is not installed.' }
$config=Get-Content $configPath -Raw | ConvertFrom-Json
$controller=Join-Path $root 'Set-GuardianProtection.ps1'
# Uninstall is an explicit switch: restore each enrolled interface's original DNS.
& $controller -Action Disable
$result=Get-Content (Join-Path $root 'guardian-result.json') -Raw | ConvertFrom-Json
if (-not $result.success) { throw "Baseline restoration failed: $($result.message)" }
foreach ($name in 'Enable','Disable','Check','Snapshot','Capture','Enroll') {
    $taskName="SJTU Guardian - $name"
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}
foreach ($baseline in @($config.baselines)) {
    foreach ($protocol in 'UDP','TCP') {
        $ruleName="SJTU Night - Block Campus DNS - $protocol - $($baseline.alias)"
        Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
            Where-Object Group -eq 'SJTU Network Mode' | Remove-NetFirewallRule
    }
}
if ($config.PSObject.Properties.Name -contains 'dohOriginal') {
    $definitions=@(
        @{address='119.29.29.29';template='https://doh.pub/dns-query'},
        @{address='2402:4e00::';template='https://doh.pub/dns-query'},
        @{address='223.5.5.5';template='https://dns.alidns.com/dns-query'},
        @{address='2400:3200::1';template='https://dns.alidns.com/dns-query'}
    )
    $bound=@(Get-DnsClientServerAddress | ForEach-Object ServerAddresses | Where-Object { $_ })
    foreach ($definition in $definitions) {
        $current=Get-DnsClientDohServerAddress -ServerAddress $definition.address -ErrorAction SilentlyContinue
        if (-not $current -or $current.DohTemplate -ne $definition.template) { continue }
        $old=@($config.dohOriginal | Where-Object address -eq $definition.address | Select-Object -First 1)
        if ($old.Count -gt 0) {
            Set-DnsClientDohServerAddress -ServerAddress $definition.address -DohTemplate $old[0].template -AutoUpgrade ([bool]$old[0].autoUpgrade) -AllowFallbackToUdp ([bool]$old[0].fallback)
        }
        elseif ($definition.address -notin $bound) {
            Remove-DnsClientDohServerAddress -ServerAddress $definition.address -ErrorAction SilentlyContinue
        }
    }
}
$desktop=[Environment]::GetFolderPath('Desktop')
$link=Join-Path $desktop '校园网网络管家.lnk'
if (Test-Path $link) { Remove-Item -LiteralPath $link }
# Keep migration backups and diagnostic files for user-controlled recovery.
Write-Host 'Guardian tasks, software-owned campus rules and desktop link removed. Original DNS restored; proxy/VPN untouched. Backups were retained.'
