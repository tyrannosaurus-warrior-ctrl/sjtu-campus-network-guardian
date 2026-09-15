# 发布测试版前清单

- [ ] `dotnet build` 成功，且没有警告。
- [ ] `Build-Release.ps1` 成功，zip 与 `.sha256.txt` 一同生成。
- [ ] 检查 zip 内不含 `ProgramData`、日志、备份、IP、MAC、订阅链接或账号。
- [ ] 在干净 Windows 11 x64 虚拟机完成安装、开启、关闭和卸载。
- [ ] 阅读 [TESTING.md](TESTING.md) 的发布阻断项；未通过项写入 Release 的“已知限制”。
- [ ] 创建 GitHub `v0.1.0-beta.1` Pre-release，上传 zip 与 SHA-256 文件。
- [ ] Release 首行写明“未签名测试版，仅面向上海交通大学校园网”。
- [ ] 不在 Release 中附带或要求用户关闭 Windows Defender/SmartScreen。
