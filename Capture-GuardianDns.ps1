#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'SJTU-Network-Mode'
$result=Join-Path $root 'guardian-capture-result.json'
$campus=@('202.120.2.101','202.120.2.100','2001:da8:8000:6180:150:112:26:40','2001:da8:8000:1:202:120:2:101')
$temp=Join-Path $root ('capture-'+[guid]::NewGuid().ToString('N'))
$started=$false; $ownedFilter=$false
$summary=[ordered]@{ timestamp=(Get-Date).ToString('o'); seconds=0; result='refused'; campusCount=0; other53Count=0;
    inbound53Count=0; unparsedCount=0; destinations=@(); message='检查未运行' }
try {
    $status=(& pktmon status 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or @($status -split "`r?`n" | Where-Object { $_.Trim() }).Count -ne 1) {
        throw 'Pktmon 状态不是明确的“未运行”；为避免打断他人的抓包，拒绝启动。'
    }
    $filters=(& pktmon filter list 2>&1 | Out-String)
    $filterLines=@($filters -split "`r?`n" | Where-Object { $_.Trim() })
    if ($LASTEXITCODE -ne 0 -or $filterLines.Count -ne 2 -or $filterLines[1].Trim().Length -gt 8) {
        throw 'Pktmon 已有过滤器或无法确认过滤器为空；本次不运行，也不清除现有过滤器。'
    }
    New-Item -ItemType Directory -Path $temp | Out-Null
    & pktmon filter add Guardian53 -p 53 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '无法添加只观察端口 53 的过滤器。' }
    $ownedFilter=$true
    $etl=Join-Path $temp 'guard.etl'; $txt=Join-Path $temp 'guard.txt'
    & pktmon start -c --comp nics --pkt-size 64 --file-name $etl --file-size 2 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '无法启动 Pktmon。' }
    $started=$true
    # Generate one fresh DNS lookup; the name is under example.com and contains no user data.
    $name=([guid]::NewGuid().ToString('N')+'.example.com')
    Resolve-DnsName $name -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 10
    & pktmon stop | Out-Null
    $started=$false
    & pktmon etl2txt $etl --out $txt --brief | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $txt)) { throw '捕获已结束，但不能可靠转换为文本；结论为无法判断。' }
    $lines=@(Get-Content $txt | Where-Object { $_ -match '53' -and $_ -match '(UDP|TCP|udp|tcp)' -and $_ -match '\s>\s' })
    $packetPattern='(?<src>(?:\d{1,3}\.){3}\d{1,3}|[0-9a-fA-F:]+)\.(?<srcPort>\d+)\s*>\s*(?<dst>(?:\d{1,3}\.){3}\d{1,3}|[0-9a-fA-F:]+)\.(?<dstPort>\d+)'
    $records=@($lines | ForEach-Object {
        $line=$_
        if ($line -notmatch $packetPattern) { $summary.unparsedCount++; return }
        $source=$Matches.src; $dest=$Matches.dst; $srcPort=[int]$Matches.srcPort; $dstPort=[int]$Matches.dstPort
        if ($srcPort -eq 53 -and $dstPort -ne 53) { $summary.inbound53Count++; return }
        if ($dstPort -ne 53) { return }
        [pscustomobject]@{ destination=$dest; protocol=if ($line -match 'UDP|udp') {'UDP'} else {'TCP'};
            campus=($dest -in $campus); source=$source }
    })
    $summary.seconds=10
    $summary.campusCount=@($records | Where-Object campus).Count
    $summary.other53Count=@($records | Where-Object { -not $_.campus }).Count
    $summary.destinations=@($records | Group-Object destination,protocol | ForEach-Object {
        @{ destination=$_.Group[0].destination; protocol=$_.Group[0].protocol; count=$_.Count }
    })
    if ($summary.campusCount -gt 0) {
        $summary.result='campus53'; $summary.message="在 10 秒窗口内观察到 $($summary.campusCount) 条涉及校园 DNS 的 53 端口记录；请检查是否为出站与哪个进程发出。"
    }
    elseif ($summary.other53Count -gt 0) {
        $summary.result='other53'; $summary.message="未观察到校园 DNS 53；观察到 $($summary.other53Count) 条向其他地址发出的 53 端口记录，可能来自代理或其他应用；不等于整机 DNS 完全加密。"
    }
    elseif ($summary.unparsedCount -gt 0) {
        $summary.result='inconclusive'; $summary.message='有 53 端口候选记录无法解析方向；不能据此判断是否存在明文 DNS 泄漏。'
    }
    elseif ($summary.inbound53Count -gt 0) {
        $summary.result='inbound53'; $summary.message="未观察到出站 53；观察到 $($summary.inbound53Count) 条入站 53 记录。这不代表永久无泄漏；可在代理关闭时复测。"
    }
    else {
        $summary.result='none53'; $summary.message='10 秒窗口内未观察到物理网卡上的 53 端口包；这不是永久保证，也不能证明校园网无法观察其他流量。'
    }
}
catch { $summary.result='refused'; $summary.message=$_.Exception.Message }
finally {
    if ($started) { & pktmon stop | Out-Null }
    if ($ownedFilter) {
        $filtersAfter=(& pktmon filter list 2>&1 | Out-String)
        if ($filtersAfter -match 'Guardian53' -and @($filtersAfter -split "`r?`n" | Where-Object { $_ -match 'Filter|筛选器|Guardian53' }).Count -le 3) {
            & pktmon filter remove | Out-Null
        }
        else { $summary.message += ' 过滤器状态在检查中变化，未清除任何过滤器。' }
    }
    $resolved=[System.IO.Path]::GetFullPath($temp)
    $expected=[System.IO.Path]::GetFullPath($root).TrimEnd('\')+'\capture-'
    if ($resolved.StartsWith($expected,[System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    $summary.timestamp=(Get-Date).ToString('o')
    $summary | ConvertTo-Json -Depth 6 | Set-Content $result -Encoding UTF8
}

