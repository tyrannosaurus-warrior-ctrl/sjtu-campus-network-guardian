# 交大校园网网络管家（测试版）

> Windows 11 x64 · v0.1.0-beta.2 · 未签名开发测试版 · 仅面向上海交通大学校园网

这个工具只处理 DNS：在你确认的交大有线或 Wi-Fi 网卡上启用严格 DoH，并阻止已登记校园 DNS 的普通 53 端口查询。

它不会隐藏目标 IP、连接时间或所有流量，也不会修改快柠檬、Surfshark、Clash、Mihomo 或其他代理/VPN 设置，更不保证解除非 DNS 限速。

## 先记住三件事

1. 只从 [Releases](https://github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/releases/latest) 下载 ZIP，不要下载 `Source code`。
2. 安装必须使用“以管理员身份运行”的 Windows PowerShell 5.1；不要直接右键选择“使用 PowerShell 运行”。
3. 安装后保护默认关闭。只有在应用中点击“开启保护”后才会修改选定网卡的 DNS。

## 一、安装前检查

- Windows 11 64 位。
- 当前用户可以通过 UAC 管理员授权；如果电脑要求输入其他管理员账号，请使用你有权使用的管理员账号。
- 已连接交大校园有线网络或 Wi-Fi，或者准备在第一次开启保护时连接。
- ZIP 已经完整解压到文件夹，不能直接在 ZIP 压缩包内部运行脚本。
- 不需要安装 Python 或 .NET。

## 二、下载并校验安装包

打开 [v0.1.0-beta.2 Release](https://github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/releases/tag/v0.1.0-beta.2)，下载：

`SJTU-Network-Guardian-0.1.0-beta.2-win-x64.zip`

建议在下载后校验 SHA-256。下面的命令适用于浏览器默认下载目录：

```powershell
$zip = Join-Path $env:USERPROFILE 'Downloads\SJTU-Network-Guardian-0.1.0-beta.2-win-x64.zip'
Get-FileHash -LiteralPath $zip -Algorithm SHA256
```

应得到：

```
E02433C2DE02F3E2B9135CA88EA94E0BFED79363152BDD199D2AFC88C95AE21E
```

如果校验值不同，请删除该 ZIP，重新从本项目 Release 下载；不要关闭 Windows 安全功能，也不要使用第三方重新打包的文件。

## 三、解压

在资源管理器中右键 ZIP，选择“全部解压缩”。建议直接解压到桌面，得到类似下面的文件夹：

`C:\Users\你的用户名\Desktop\SJTU-Network-Guardian-0.1.0-beta.2-win-x64`

打开这个文件夹，确认能看到 `Install-Guardian.ps1`、`Uninstall-Guardian.ps1` 和 `SjtuGuardian.exe`。

## 四、安装（请严格按下面做）

### 1. 打开管理员 Windows PowerShell 5.1

打开开始菜单，搜索 **Windows PowerShell**，右键它，选择 **以管理员身份运行**，然后在 UAC 窗口选择“是”。

注意：这里要选“Windows PowerShell”，不是“PowerShell 7”。如果不确定，可以在窗口中执行：

```powershell
$PSVersionTable.PSVersion
```

主版本应为 `5`。

### 2. 运行安装命令

如果你按上面的建议解压到了桌面，直接复制下面整段命令并回车：

```powershell
$pkg = Join-Path $env:USERPROFILE 'Desktop\SJTU-Network-Guardian-0.1.0-beta.2-win-x64'
$winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $winPs -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'Install-Guardian.ps1')
```

如果你解压到了其他位置，只需要把 `$pkg` 改成实际解压目录，例如：

```powershell
$pkg = 'D:\Downloads\SJTU-Network-Guardian-0.1.0-beta.2-win-x64'
```

`-ExecutionPolicy Bypass` 只对这一次安装进程有效，不会修改电脑的全局执行策略。

看到下面的提示就表示安装完成：

```
Installed. Protection is OFF by default.
```

安装会创建桌面快捷方式“校园网网络管家”、程序目录和计划任务。首次安装不会立刻改 DNS。

## 五、第一次使用

1. 确认电脑已连接交大校园有线或 Wi-Fi。
2. 双击桌面的“校园网网络管家”。
3. 在界面中确认实际使用的校园物理网卡，例如 `WLAN` 或 `Ethernet`。
4. 点击“开启保护”，等待界面显示成功。
5. 需要恢复原 DNS 时点击“关闭保护”。

如果开启后认证门户打不开：先“关闭保护”，完成校园网认证，再重新“开启保护”。

保护模式下 DoH 服务不可达时，程序会拒绝回退到普通 DNS，可能表现为网页暂时无法解析；恢复网络后可以再次检查。

## 六、常见错误

### “running scripts is disabled on this system”

说明你使用了右键菜单或普通 PowerShell，执行策略阻止了未签名脚本。关闭当前窗口，重新打开“以管理员身份运行”的 Windows PowerShell，然后执行上面的完整安装命令。不要使用 `Set-ExecutionPolicy Unrestricted`，也不要关闭 Windows 安全功能。

### “contains a #requires statement for running as Administrator”

说明当前窗口没有管理员权限。关闭窗口，重新按“以管理员身份运行”打开 Windows PowerShell。

### “快捷方式路径名称需以 .lnk 或 .url 结尾”

这是旧版 `v0.1.0-beta.1` 安装脚本的编码问题。请不要手工改脚本；删除旧解压目录，重新下载 `v0.1.0-beta.2` 或更新版本，并按本文第四节的命令安装。

### Windows 显示“未知发布者”

这是因为测试版尚未购买代码签名证书。请核对 Release 来源和 SHA-256；不要为了安装而关闭 Defender、SmartScreen 或其他安全功能。

## 七、卸载

卸载也必须在管理员 Windows PowerShell 5.1 中执行：

```powershell
$pkg = Join-Path $env:USERPROFILE 'Desktop\SJTU-Network-Guardian-0.1.0-beta.2-win-x64'
$winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $winPs -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg 'Uninstall-Guardian.ps1')
```

卸载会恢复已记录的原 DNS，删除 Guardian 计划任务和软件创建的校园 DNS 防火墙规则；不会修改代理/VPN 设置。配置备份和诊断文件会保留，便于人工恢复和反馈问题。

## 它会做什么／不会做什么

| 会做 | 不会做 |
| --- | --- |
| 在你确认的校园物理网卡设置严格 DoH | 修改 IP、网关、路由或代理/VPN |
| 记录原 DNS，并在关闭/卸载时恢复 | 自动在白天/夜晚切换或主动断开游戏 |
| 阻断指向已登记校园 DNS 的 TCP/UDP 53 | 证明“从未被监听”或保证游戏延迟 |

## 反馈问题

请在 [Issues](https://github.com/tyrannosaurus-warrior-ctrl/sjtu-campus-network-guardian/issues) 中说明 Windows 版本、网络类型（有线/Wi-Fi）、是否使用代理/VPN，以及应用中显示的错误信息。

不要上传 IP、MAC、校园账号、代理订阅链接、原始抓包或完整的 `C:\ProgramData\SJTU-Network-Mode` 文件夹。

本项目与上海交通大学、DNS 服务商、腾讯、英雄联盟及任何 VPN 服务商均无官方关联。它是开发测试软件，请先在可恢复的网络环境中验证“关闭保护”能够恢复原 DNS。
