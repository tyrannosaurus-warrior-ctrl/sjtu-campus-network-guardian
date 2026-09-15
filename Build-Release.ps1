[CmdletBinding()]
param([string]$Version = '0.1.0-beta')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$out = Join-Path $root 'artifacts'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$publish = Join-Path $out 'publish'
Remove-Item -LiteralPath $publish -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish (Join-Path $root 'app\SjtuGuardian.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -o $publish
# PDBs can include local source paths and are not needed by end users.
Get-ChildItem -LiteralPath $publish -Filter '*.pdb' -File | Remove-Item -Force
Copy-Item -LiteralPath (Join-Path $root 'Install-Guardian.ps1') -Destination $publish
Copy-Item -LiteralPath (Join-Path $root 'Uninstall-Guardian.ps1') -Destination $publish
Copy-Item -LiteralPath (Join-Path $root 'Set-GuardianProtection.ps1') -Destination $publish
Copy-Item -LiteralPath (Join-Path $root 'Capture-GuardianDns.ps1') -Destination $publish
Copy-Item -LiteralPath (Join-Path $root 'Grant-GuardianTaskRun.ps1') -Destination $publish
$zip = Join-Path $out "SJTU-Network-Guardian-$Version-win-x64.zip"
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip
Get-FileHash -Algorithm SHA256 $zip | Format-List | Out-File ("$zip.sha256.txt") -Encoding utf8
Write-Host "Created $zip"
