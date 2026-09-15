#Requires -RunAsAdministrator
[CmdletBinding()]
param([ValidateSet('Enable','Disable','Check','Snapshot','Enroll')][string]$Action = 'Check')
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramData 'SJTU-Network-Mode'
$configPath = Join-Path $root 'guardian-config.json'
$resultPath = Join-Path $root 'guardian-result.json'
$campusDns = @('202.120.2.101','202.120.2.100','202.112.26.40','2001:da8:8000:6180:150:112:26:40','2001:da8:8000:1:202:120:2:101')
$resolvers = @(
    @{ Address='223.5.5.5'; Template='https://dns.alidns.com/dns-query' },
    @{ Address='2400:3200::1'; Template='https://dns.alidns.com/dns-query' }
)
$managedDns = @($resolvers | ForEach-Object Address)
$group = 'SJTU Network Mode'

function Save-Config($config) {
    $tmp = "$configPath.tmp"
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $configPath -Force
}
function Save-Result($success,$changed,$message,$config,$interfaces) {
    [ordered]@{ timestamp=(Get-Date).ToString('o'); action=$Action; success=$success;
        changed=$changed; enabled=[bool]$config.enabled; message=$message; interfaces=@($interfaces) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}
function Dns-For($index) {
    @(Get-DnsClientServerAddress -InterfaceIndex $index -ErrorAction SilentlyContinue | ForEach-Object ServerAddresses | Where-Object { $_ })
}
function Is-Managed($addresses) {
    $a=@($addresses); $a.Count -gt 0 -and @($a | Where-Object { $_ -notin $managedDns }).Count -eq 0
}
function Is-Strict($addresses) {
    foreach ($addr in @($addresses)) {
        $entry=Get-DnsClientDohServerAddress -ServerAddress $addr -ErrorAction SilentlyContinue
        if (-not $entry -or -not $entry.AutoUpgrade -or $entry.AllowFallbackToUdp) { return $false }
    }
    return $true
}
function Get-PhysicalTargets($config) {
    $known=@($config.baselines | ForEach-Object interfaceGuid)
    @(Get-NetAdapter -IncludeHidden | Where-Object {
        $_.HardwareInterface -and ($_.InterfaceGuid.ToString() -in $known -or
            @((Dns-For $_.ifIndex) | Where-Object { $_ -in $campusDns }).Count -gt 0)
    })
}
function Get-Rule($alias,$protocol) {
    Get-NetFirewallRule -DisplayName "SJTU Night - Block Campus DNS - $protocol - $alias" -ErrorAction SilentlyContinue
}
function Rule-OK($alias,$protocol,$enabled) {
    $rule=Get-Rule $alias $protocol
    if (-not $rule) { return -not $enabled }
    $want=if ($enabled) {'True'} else {'False'}
    if ($rule.Enabled.ToString() -ne $want) { return $false }
    $port=$rule | Get-NetFirewallPortFilter
    $addr=$rule | Get-NetFirewallAddressFilter
    $actual=@($addr.RemoteAddress | Sort-Object -Unique)
    $expected=@($campusDns | Sort-Object -Unique)
    return ($port.RemotePort -eq '53' -and $port.Protocol -eq $protocol -and
        $actual.Count -eq $expected.Count -and @($actual | Where-Object { $_ -notin $expected }).Count -eq 0)
}
function Set-Rule($alias,$protocol,$enabled) {
    $rule=Get-Rule $alias $protocol
    if (-not $rule -and $enabled) {
        $rule=New-NetFirewallRule -DisplayName "SJTU Night - Block Campus DNS - $protocol - $alias" -Group $group -Direction Outbound -Action Block -Profile Any -InterfaceAlias $alias -Protocol $protocol -RemotePort 53 -RemoteAddress $campusDns -Enabled False
    }
    if ($rule) {
        if (-not (Rule-OK $alias $protocol $enabled)) {
            # Keep ownership narrow: replace only this software-owned, exact-name rule.
            $rule | Remove-NetFirewallRule
            if ($enabled) {
                New-NetFirewallRule -DisplayName "SJTU Night - Block Campus DNS - $protocol - $alias" -Group $group -Direction Outbound -Action Block -Profile Any -InterfaceAlias $alias -Protocol $protocol -RemotePort 53 -RemoteAddress $campusDns -Enabled True | Out-Null
                return $true
            }
            return $true
        }
        $want=if ($enabled) {'True'} else {'False'}
        if ($rule.Enabled.ToString() -ne $want) { Set-NetFirewallRule -InputObject $rule -Enabled $want | Out-Null; return $true }
    }
    return $false
}
function Test-DohReachable {
    # A real DoH query, not merely an open TCP/443 port. The payload asks for
    # example.com A and has no user-specific name.
    try {
        $uri='https://dns.alidns.com/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE'
        $response=Invoke-WebRequest -Uri $uri -Headers @{Accept='application/dns-message'} -UseBasicParsing -TimeoutSec 5
        return ($response.StatusCode -eq 200 -and $response.Content.Length -gt 12)
    }
    catch { return $false }
}
function Ensure-StrictDoh {
    foreach ($r in $resolvers) {
        $entry=Get-DnsClientDohServerAddress -ServerAddress $r.Address -ErrorAction SilentlyContinue
        if ($entry -and $entry.DohTemplate -eq $r.Template -and $entry.AutoUpgrade -and -not $entry.AllowFallbackToUdp) { continue }
        if ($entry) { Set-DnsClientDohServerAddress -ServerAddress $r.Address -DohTemplate $r.Template -AutoUpgrade $true -AllowFallbackToUdp $false | Out-Null }
        else { Add-DnsClientDohServerAddress -ServerAddress $r.Address -DohTemplate $r.Template -AutoUpgrade $true -AllowFallbackToUdp $false | Out-Null }
    }
}
function Get-OriginalBaseline($adapter) {
    $id=([guid]$adapter.InterfaceGuid).ToString('D')
    $key4="HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{$id}"
    $key6="HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\{$id}"
    $static4=(Get-ItemProperty -Path $key4 -Name NameServer -ErrorAction SilentlyContinue).NameServer
    $static6=(Get-ItemProperty -Path $key6 -Name NameServer -ErrorAction SilentlyContinue).NameServer
    [ordered]@{ interfaceGuid=$adapter.InterfaceGuid.ToString(); alias=$adapter.Name;
        mode=if ([string]::IsNullOrWhiteSpace($static4) -and [string]::IsNullOrWhiteSpace($static6)) {'dhcp'} else {'static'};
        addresses=@(Dns-For $adapter.ifIndex | Where-Object { $_ -notlike 'fec0:*' }); captured=(Get-Date).ToString('o') }
}
function Restore-Baseline($adapter,$baseline) {
    if ($baseline.mode -eq 'dhcp') { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses }
    else { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($baseline.addresses) }
}
function Write-Snapshot($config,$adapters) {
    $proxy=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    $all=@(Get-NetAdapter -IncludeHidden | ForEach-Object {
        $a=$_; [ordered]@{ name=$a.Name; description=$a.InterfaceDescription; guid=$a.InterfaceGuid.ToString();
            index=$a.ifIndex; status=$a.Status.ToString(); physical=[bool]$a.HardwareInterface;
            mac=$a.MacAddress; dns=@(Dns-For $a.ifIndex);
            ip=@(Get-NetIPAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue | ForEach-Object IPAddress);
            gateways=@(Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix @('0.0.0.0/0','::/0') -ErrorAction SilentlyContinue | ForEach-Object NextHop) }
    })
    $doh=@($resolvers | ForEach-Object {
        $x=Get-DnsClientDohServerAddress -ServerAddress $_.Address -ErrorAction SilentlyContinue
        [ordered]@{ address=$_.Address; template=if ($x) {$x.DohTemplate} else {$null};
            autoUpgrade=if ($x) {[bool]$x.AutoUpgrade} else {$false}; fallback=if ($x) {[bool]$x.AllowFallbackToUdp} else {$null} }
    })
    [ordered]@{timestamp=(Get-Date).ToString('o'); enabled=[bool]$config.enabled; adapters=$all; doh=$doh;
        proxy=@{ enabled=[bool]$proxy.ProxyEnable; server=[string]$proxy.ProxyServer };
        defaultRoutes=@(Get-NetRoute -DestinationPrefix @('0.0.0.0/0','::/0') -ErrorAction SilentlyContinue |
            ForEach-Object { @{ interfaceIndex=$_.InterfaceIndex; nextHop=$_.NextHop; prefix=$_.DestinationPrefix; metric=$_.RouteMetric } });
        campusRules=@($adapters | ForEach-Object { $a=$_; 'UDP','TCP' | ForEach-Object { @{ alias=$a.Name; protocol=$_; valid=(Rule-OK $a.Name $_ $config.enabled) } } }) } |
        ConvertTo-Json -Depth 10 | Set-Content (Join-Path $root 'guardian-snapshot.json') -Encoding UTF8
}

$changed=$false; $dnsChanged=$false; $cacheCleared=$false; $names=@(); $config=$null
$dnsRestore=@()
$priorEnabled=$null
try {
    if (-not (Test-Path $configPath)) { throw 'Guardian config is missing; run the migration installer first.' }
    $config=Get-Content $configPath -Raw | ConvertFrom-Json
    $priorEnabled=[bool]$config.enabled
    if ($Action -eq 'Enroll') {
        $requestPath=Join-Path (Join-Path $env:LOCALAPPDATA 'SJTU Guardian') 'enroll.json'
        if (-not (Test-Path $requestPath)) { throw 'No adapter enrollment request exists.' }
        $request=Get-Content $requestPath -Raw | ConvertFrom-Json
        $guid=[guid]::Empty
        if (-not [guid]::TryParse([string]$request.interfaceGuid,[ref]$guid)) { throw 'Enrollment GUID is invalid.' }
        $match=@(Get-NetAdapter -IncludeHidden | Where-Object { $_.HardwareInterface -and ([guid]$_.InterfaceGuid) -eq $guid })
        if ($match.Count -ne 1) { throw 'Enrollment must select exactly one physical network adapter.' }
        if (@($config.baselines | Where-Object { ([guid]$_.interfaceGuid) -eq $guid }).Count -eq 0) {
            $config.baselines=@($config.baselines)+@(Get-OriginalBaseline $match[0])
            Save-Config $config
        }
        Remove-Item -LiteralPath $requestPath
    }
    if ($Action -eq 'Enable') { $config.enabled=$true }
    if ($Action -eq 'Disable') { $config.enabled=$false }
    $adapters=@(Get-PhysicalTargets $config)
    $names=@($adapters | ForEach-Object Name)
    if ($Action -ne 'Snapshot') {
        foreach ($adapter in $adapters) {
            $baseline=@($config.baselines | Where-Object interfaceGuid -eq $adapter.InterfaceGuid.ToString() | Select-Object -First 1)
            if ($baseline.Count -eq 0) {
                $config.baselines=@($config.baselines)+@(Get-OriginalBaseline $adapter)
                Save-Config $config
                $baseline=@($config.baselines | Where-Object interfaceGuid -eq $adapter.InterfaceGuid.ToString() | Select-Object -First 1)
            }
            $current=@(Dns-For $adapter.ifIndex)
            if ($config.enabled) {
                if (-not (Is-Managed $current) -or -not (Is-Strict $current)) {
                    if (-not (Test-DohReachable)) { throw 'Ali DoH TCP443 is unreachable; DNS and firewall were not changed.' }
                    Ensure-StrictDoh
                    if (-not (Is-Managed $current)) {
                        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $managedDns
                        $dnsRestore+=@{ adapter=$adapter; addresses=$current; baseline=$baseline[0] }
                        $changed=$true
                        $dnsChanged=$true
                        Clear-DnsClientCache
                        $cacheCleared=$true
                        Resolve-DnsName 'prod-rso.lol.qq.com' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop | Out-Null
                        Resolve-DnsName 'www.qq.com' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop | Out-Null
                    }
                }
                foreach ($protocol in 'UDP','TCP') { if (Set-Rule $adapter.Name $protocol $true) { $changed=$true } }
            }
            else {
                if (Is-Managed $current) { Restore-Baseline $adapter $baseline[0]; $changed=$true; $dnsChanged=$true }
                foreach ($protocol in 'UDP','TCP') { if (Set-Rule $adapter.Name $protocol $false) { $changed=$true } }
            }
        }
        if ($dnsChanged -and -not $cacheCleared) { Clear-DnsClientCache }
    }
    if ($Action -in @('Enable','Disable')) { Save-Config $config }
    Write-Snapshot $config $adapters
    Save-Result $true $changed 'Requested state checked; no proxy or VPN settings were modified.' $config $names
}
catch {
    foreach ($restore in $dnsRestore) {
        try {
            if (@($restore.addresses).Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $restore.adapter.ifIndex -ServerAddresses @($restore.addresses)
            }
            else { Restore-Baseline $restore.adapter $restore.baseline }
        }
        catch { }
    }
    if ($dnsRestore.Count -gt 0) { Clear-DnsClientCache -ErrorAction SilentlyContinue }
    if ($config) {
        if ($null -ne $priorEnabled -and $Action -in @('Enable','Disable')) {
            $config.enabled=$priorEnabled
            Save-Config $config
        }
        Save-Result $false $changed $_.Exception.Message $config $names
    }
    throw
}

