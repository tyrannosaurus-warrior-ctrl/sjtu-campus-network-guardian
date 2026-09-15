#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'SJTU-Network-Mode'
$service=New-Object -ComObject Schedule.Service
$service.Connect()
$folder=$service.GetFolder('\')
$sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$names=@('SJTU Guardian - Enable','SJTU Guardian - Disable','SJTU Guardian - Check',
    'SJTU Guardian - Snapshot','SJTU Guardian - Capture','SJTU Guardian - Enroll')
$before=@()
foreach ($name in $names) {
    $task=$folder.GetTask($name)
    $sddl=$task.GetSecurityDescriptor(0xF)
    $before+=@{ name=$name; sddl=$sddl }
    $old="(A;;FR;;;$sid)"; $new="(A;;FRFX;;;$sid)"
    if ($sddl.Contains($new)) { continue }
    if (-not $sddl.Contains($old)) { throw "Expected user-only read ACE is missing for $name; not broadening permissions." }
    $task.SetSecurityDescriptor($sddl.Replace($old,$new),0)
}
@{ timestamp=(Get-Date).ToString('o'); userSid=$sid; previousAcls=$before } |
    ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root 'guardian-task-acl-backup.json') -Encoding UTF8
