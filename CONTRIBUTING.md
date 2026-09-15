# 贡献指南

欢迎提交文档、无障碍改进、测试结果和修复。请保持“普通人读得懂”的中文；把 DNS、路由和端口等术语留给可展开的技术详情。

提交前至少运行：

```powershell
dotnet build .\app\SjtuGuardian.csproj -c Release
```

涉及网络配置的修改必须说明：初始状态、预期修改、失败回滚、DHCP 和静态 IP 行为、IPv4/IPv6 行为，以及对 VPN/本机代理的影响。不得提交真实 IP、MAC、校园账号、代理链接、抓包、备份或日志。
