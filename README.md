# 交大校园网网络管家（测试版）

> **Windows 11 x64 · 未签名开发测试版 · 仅面向上海交通大学校园网**

它让 Windows 用加密方式查询网站地址，并阻止已知校园 DNS 的普通 53 端口查询。这样可以避免校园 DNS 直接返回“找不到网站”。它**不能**隐藏你访问的目标 IP、连接时间或所有流量；也不承诺绕过任何非 DNS 的限速。

## 三步使用

1. 从本项目的 Release 下载 `SJTU-Network-Guardian-...zip`，解压到本地。
2. 右键 `Install-Guardian.ps1`，选择“使用 PowerShell 运行”，按提示接受管理员授权。
3. 打开桌面的“校园网网络管家”，点击“开启保护”。需要恢复原设置时点击“关闭保护”；卸载时运行 `Uninstall-Guardian.ps1`。

Windows 可能提示这是“未知发布者”，因为本测试版尚未签名。请只从本项目的 GitHub Release 下载，并核对 Release 提供的 SHA-256 校验值。不要为了安装而关闭 Windows 安全功能。

## 它会做什么／不会做什么

| 会做 | 不会做 |
| --- | --- |
| 在你确认的校园物理网卡设置严格 DoH | 修改 IP、网关、路由、快柠檬、Surfshark 或其他 VPN |
| 记录该网卡原有 DNS，以便关闭和卸载时恢复 | 自动在白天／夜晚切换，或主动断开游戏 |
| 阻断指向已登记校园 DNS 的 TCP/UDP 53 | 证明“没有被监听”，或承诺游戏延迟 |

严格模式下，DoH 服务不可用时 DNS 会失败，不会退回校园明文 DNS。首次安装不会立刻修改网络；只有在应用中开启保护时才更改 DNS。

## 适用与不适用

- 已验证目标：Windows 11 x64、交大有线或 Wi-Fi、DHCP 或静态 IP。
- 静态 IP：程序只记录和替换 DNS；不会变更静态 IP 地址、子网掩码、网关或路由。请先在测试时段确认关闭保护可恢复原 DNS。
- 代理/VPN：程序不改它们的设置。虚拟网卡不会被纳入保护。代理本身是否使用明文 DNS，需要其自身文档或本软件的按需检查确认。
- 认证门户：若开启保护后认证页打不开，先在应用中关闭保护，完成认证后再开启。

## 需要反馈什么

请用 Issue 模板报告问题，说明 Windows 版本、网络类型（有线/Wi-Fi）、是否使用代理/VPN，以及是否能通过“预览匿名诊断导出”复现。**不要**上传 IP、MAC、校园账号、代理订阅链接、原始抓包或完整 `C:\ProgramData\SJTU-Network-Mode` 文件夹。

## 给贡献者

构建需要 .NET 10 SDK：

```powershell
dotnet build .\app\SjtuGuardian.csproj -c Release
.\Build-Release.ps1
```

发布前请阅读 [SECURITY.md](SECURITY.md)、[CONTRIBUTING.md](CONTRIBUTING.md) 和 [测试清单](docs/TESTING.md)。本项目与上海交通大学、DNS 服务商、腾讯、英雄联盟及任何 VPN 服务商均无官方关联。
