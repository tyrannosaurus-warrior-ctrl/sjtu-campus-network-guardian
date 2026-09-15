using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Windows;
using Microsoft.Win32;

namespace SjtuGuardian;

public partial class MainWindow : Window
{
    private sealed record AdapterChoice(string Name, string Guid)
    {
        public override string ToString() => Name;
    }
    private readonly string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "SJTU-Network-Mode");
    private bool enabled = true;
    private static readonly string[] campusDns = ["202.120.2.101", "202.120.2.100", "202.112.26.40", "2001:da8:8000:6180:150:112:26:40", "2001:da8:8000:1:202:120:2:101"];

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await RefreshAsync(false);
    }

    private static JsonElement Prop(JsonElement obj, string name) => obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(name, out var p) ? p : default;
    private static string Str(JsonElement obj, string name) => Prop(obj, name).ValueKind == JsonValueKind.String ? Prop(obj, name).GetString() ?? "" : "";
    private static bool Bool(JsonElement obj, string name) => Prop(obj, name).ValueKind == JsonValueKind.True;
    private static IEnumerable<JsonElement> Items(JsonElement obj, string name) => Prop(obj, name).ValueKind == JsonValueKind.Array ? Prop(obj, name).EnumerateArray() : [];
    private static IEnumerable<string> Strings(JsonElement obj, string name) => Items(obj, name).Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString() ?? "");
    private JsonDocument ReadJson(string filename) => JsonDocument.Parse(File.ReadAllText(Path.Combine(root, filename)));

    private async Task RefreshAsync(bool runAdminSnapshot)
    {
        try
        {
            if (runAdminSnapshot) await RunTaskAsync("Snapshot", "guardian-snapshot.json");
            using var config = ReadJson("guardian-config.json");
            using var snapshot = ReadJson("guardian-snapshot.json");
            enabled = Bool(config.RootElement, "enabled");
            ToggleButton.Content = enabled ? "关闭保护" : "开启保护";
            Headline.Text = enabled ? "保护已开启" : "保护已关闭（手动选择已保留）";
            var adapters = Items(snapshot.RootElement, "adapters").ToArray();
            var known = Items(config.RootElement, "baselines").Select(b => Str(b, "interfaceGuid")).ToHashSet(StringComparer.OrdinalIgnoreCase);
            EnrollmentChoices.ItemsSource = adapters.Where(a => Bool(a, "physical") && !known.Contains(Str(a, "guid"))).Select(a => new AdapterChoice(Str(a, "name"), Str(a, "guid"))).ToArray();
            EnrollmentChoices.SelectedIndex = EnrollmentChoices.Items.Count > 0 ? 0 : -1;
            var physical = adapters.Where(a => Bool(a, "physical") && Str(a, "status") == "Up").ToArray();
            var defaultPhysical = physical.Where(a => Items(a, "gateways").Any()).ToArray();
            var proxy = Prop(snapshot.RootElement, "proxy");
            var proxyText = Bool(proxy, "enabled") ? $"系统代理已启用：{Str(proxy, "server")}" : "系统代理未启用";
            if (Str(proxy, "server").Contains("127.0.0.1:"))
            {
                var portString = Str(proxy, "server").Split("127.0.0.1:").Last().Split(';', '/').First();
                if (int.TryParse(portString, out var port))
                {
                    try { using var c = new TcpClient(); using var token = new CancellationTokenSource(TimeSpan.FromMilliseconds(400)); await c.ConnectAsync(IPAddress.Loopback, port, token.Token); proxyText += $"；本机 {port} 端口可连接（不代表系统代理已启用）"; }
                    catch { proxyText += $"；本机 {port} 端口暂不可连接"; }
                }
            }
            var virtualDefaults = adapters.Where(a => !Bool(a, "physical") && Str(a, "status") == "Up" && Items(a, "gateways").Any()).Select(a => Str(a, "name")).ToArray();
            Summary.Text = $"校园物理链路：{string.Join("、", defaultPhysical.Select(a => Str(a, "name")))}；连接的物理网卡：{string.Join("、", physical.Select(a => Str(a, "name")))}；默认路由也存在于虚拟网卡：{(virtualDefaults.Length == 0 ? "未发现" : string.Join("、", virtualDefaults))}；{proxyText}。代理软件是否承载所有流量需由其自身确认。";
            EvidenceTime.Text = $"本机证据时间：{Str(snapshot.RootElement, "timestamp")}";
            var activeDns = defaultPhysical.SelectMany(a => Strings(a, "dns")).Distinct().ToArray();
            var strict = Items(snapshot.RootElement, "doh").All(d => Bool(d, "autoUpgrade") && !Bool(d, "fallback") && !string.IsNullOrEmpty(Str(d, "template")));
            var campusBound = activeDns.Any(d => campusDns.Contains(d, StringComparer.OrdinalIgnoreCase));
            var ruleItems = Items(snapshot.RootElement, "campusRules").ToArray();
            var rulesGood = ruleItems.Length > 0 && ruleItems.All(r => Bool(r, "valid"));
            DnsStatus.Text = $"校园物理链路 DNS：{(activeDns.Length == 0 ? "未列出" : string.Join("、", activeDns))}。阿里 DoH 自动升级/禁止 UDP 回退：{(strict ? "已配置" : "未通过")}; 校园 DNS 绑定：{(campusBound ? "发现" : "未发现")}; 定向阻断规则：{(rulesGood ? "与选择一致" : "待校验")}。配置检查不等于抓包实测；代理隧道可能改变实际出口。";
            var sb = new StringBuilder();
            foreach (var a in adapters.OrderByDescending(a => Str(a, "status") == "Up"))
                sb.AppendLine($"{Str(a, "name")} [{Str(a, "status")}] {(Bool(a, "physical") ? "物理" : "虚拟")}\n  IP: {string.Join(", ", Strings(a, "ip"))}\n  网关: {string.Join(", ", Strings(a, "gateways"))}\n  DNS: {string.Join(", ", Strings(a, "dns"))}");
            sb.AppendLine($"系统代理：{proxyText}");
            sb.AppendLine("默认路由：");
            foreach (var r in Items(snapshot.RootElement, "defaultRoutes")) sb.AppendLine($"  {Str(r, "prefix")} → {Str(r, "nextHop")} (接口 {Prop(r, "interfaceIndex")})");
            NetworkDetails.Text = sb.ToString();
        }
        catch (Exception ex)
        {
            Headline.Text = "本机状态读取失败";
            Summary.Text = ex.Message;
        }
    }

    private async Task RunTaskAsync(string action, string resultFile)
    {
        var path = Path.Combine(root, resultFile);
        var before = File.Exists(path) ? File.GetLastWriteTimeUtc(path) : DateTime.MinValue;
        var psi = new ProcessStartInfo("schtasks.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
        psi.ArgumentList.Add("/Run"); psi.ArgumentList.Add("/TN"); psi.ArgumentList.Add($"SJTU Guardian - {action}");
        using var process = Process.Start(psi) ?? throw new InvalidOperationException("无法启动计划任务命令");
        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0)
        {
            // Some Windows task policies deny a non-elevated caller even when the
            // task grants execute rights. Fall back to a UAC prompt for a fixed,
            // installed helper script; never accept arbitrary script paths/args.
            var script = action == "Capture" ? "Capture-GuardianDns.ps1" : "Set-GuardianProtection.ps1";
            var elevated = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"))
            {
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            };
            elevated.ArgumentList.Add("-NoProfile");
            elevated.ArgumentList.Add("-ExecutionPolicy"); elevated.ArgumentList.Add("Bypass");
            elevated.ArgumentList.Add("-File"); elevated.ArgumentList.Add(Path.Combine(root, script));
            if (action != "Capture") { elevated.ArgumentList.Add("-Action"); elevated.ArgumentList.Add(action); }
            using var helper = Process.Start(elevated) ?? throw new InvalidOperationException($"管理员辅助任务未启动：{stderr} {stdout}");
            await helper.WaitForExitAsync();
            if (helper.ExitCode != 0) throw new InvalidOperationException($"管理员辅助任务失败（退出码 {helper.ExitCode}）。请查看本机 guardian-result.json；原代理设置未更改。");
        }
        for (var i = 0; i < 100; i++)
        {
            if (File.Exists(path) && File.GetLastWriteTimeUtc(path) > before) return;
            await Task.Delay(300);
        }
        throw new TimeoutException("辅助任务没有在 30 秒内返回；原网络配置不会由界面直接更改。");
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await RefreshAsync(true);

    private async void Toggle_Click(object sender, RoutedEventArgs e)
    {
        var action = enabled ? "Disable" : "Enable";
        var message = enabled ? "主动关闭保护可能让正在运行的游戏或 Codex 短暂重连。是否继续？" : "开启严格 DoH 后，解析器不可达时 DNS 会失败，不会回退校园明文 DNS。是否继续？";
        if (MessageBox.Show(message, "确认切换", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        ToggleButton.IsEnabled = false;
        try
        {
            await RunTaskAsync(action, "guardian-result.json");
            using var result = ReadJson("guardian-result.json");
            if (!Bool(result.RootElement, "success")) MessageBox.Show(Str(result.RootElement, "message"), "切换失败");
            await RefreshAsync(true);
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "切换失败"); }
        finally { ToggleButton.IsEnabled = true; }
    }

    private async void Game_Click(object sender, RoutedEventArgs e)
    {
        GameResult.Text = "正在按需检测…";
        var results = new List<string>();
        try
        {
            using var snap = ReadJson("guardian-snapshot.json");
            var gw = Items(snap.RootElement, "adapters").Where(a => Bool(a, "physical") && Str(a, "status") == "Up").SelectMany(a => Strings(a, "gateways")).FirstOrDefault(g => IPAddress.TryParse(g, out _));
            if (gw != null)
            {
                using var ping = new Ping();
                try { var p = await ping.SendPingAsync(gw, 1200); results.Add(p.Status == IPStatus.Success ? $"网关 {gw}: {p.RoundtripTime} ms（ICMP）" : $"网关 {gw}: 无法测量（{p.Status}）"); }
                catch (Exception ex) { results.Add($"网关无法测量：{ex.Message}"); }
            }
            foreach (var host in new[] { "prod-rso.lol.qq.com", "tqos.gamesafe.qq.com", "ied-tqos-tgp.qq.com" })
            {
                var sw = Stopwatch.StartNew();
                try
                {
                    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(4));
                    var ips = await Dns.GetHostAddressesAsync(host, cts.Token);
                    results.Add($"{host} DNS: {sw.ElapsedMilliseconds} ms，{ips.Length} 个地址");
                    using var tcp = new TcpClient();
                    sw.Restart();
                    try { await tcp.ConnectAsync(host, 443, cts.Token); results.Add($"  TCP 443: {sw.ElapsedMilliseconds} ms（非游戏内延迟）"); }
                    catch (Exception ex) { results.Add($"  TCP 443: 无法测量/可能未开放：{ex.Message}"); }
                }
                catch (Exception ex) { results.Add($"{host} DNS 失败：{ex.Message}"); }
            }
        }
        catch (Exception ex) { results.Add($"检测异常：{ex.Message}"); }
        GameResult.Text = $"检测时间：{DateTime.Now:yyyy-MM-dd HH:mm:ss}\n" + string.Join("\n", results);
    }

    private async void Exit_Click(object sender, RoutedEventArgs e)
    {
        ExitResult.Text = "正在查询…本次会访问 api.ipify.org";
        var direct = await QueryExitAsync(false);
        var system = await QueryExitAsync(true);
        ExitResult.Text = $"检测时间：{DateTime.Now:yyyy-MM-dd HH:mm:ss}；不使用系统 HTTP 代理：{direct}；遵循系统 HTTP 代理：{system}。两者仍可能经过 VPN/TUN；这是本程序的出口，不代表所有应用。";
    }
    private static async Task<string> QueryExitAsync(bool useProxy)
    {
        try
        {
            using var handler = new HttpClientHandler { UseProxy = useProxy };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(6) };
            using var response = await client.GetAsync("https://api.ipify.org?format=json");
            response.EnsureSuccessStatusCode();
            using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            return Str(body.RootElement, "ip");
        }
        catch (Exception ex) { return $"失败（{ex.GetType().Name}: {ex.Message}）"; }
    }

    private async void Capture_Click(object sender, RoutedEventArgs e)
    {
        CaptureResult.Text = "正在按需检查（约 10 秒）…";
        try
        {
            await RunTaskAsync("Capture", "guardian-capture-result.json");
            using var data = ReadJson("guardian-capture-result.json");
            CaptureResult.Text = Str(data.RootElement, "message") + $"；检测时间：{Str(data.RootElement, "timestamp")}";
        }
        catch (Exception ex) { CaptureResult.Text = $"未能完成检查：{ex.Message}"; }
    }

    private async void Enroll_Click(object sender, RoutedEventArgs e)
    {
        if (EnrollmentChoices.SelectedItem is not AdapterChoice selected) { MessageBox.Show("没有未管理的物理网卡。"); return; }
        if (MessageBox.Show($"确认“{selected.Name}”正用于校园网吗？本操作不会修改 IP/网关，但在保护开启时会配置严格 DoH。", "加入保护", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        try
        {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SJTU Guardian");
            Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory, "enroll.json"), JsonSerializer.Serialize(new { interfaceGuid = selected.Guid }));
            await RunTaskAsync("Enroll", "guardian-result.json");
            await RefreshAsync(true);
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "加入失败"); }
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var text = $"校园网网络管家匿名诊断\n导出时间：{DateTime.Now:yyyy-MM-dd HH:mm:ss}\n保护：{(enabled ? "开启" : "关闭")}\n状态：{Headline.Text}\nDNS配置结论：{(DnsStatus.Text.Contains("未通过") ? "严格DoH待校验" : "严格DoH已配置")}\n端口53检查：{(CaptureResult.Text.StartsWith("未运行") ? "未运行" : "已运行；目的地址不导出")}\n游戏快检：{(GameResult.Text.Length == 0 ? "未运行" : "已运行；网关地址不导出")}\n公网出口检查：{(ExitResult.Text == "未查询" ? "未查询" : "已运行；IP不导出")}\n所有 IP、MAC、网卡设备名和代理节点均未导出。";
        // The preview intentionally contains only conclusions, not raw snapshot fields.
        if (MessageBox.Show(text + "\n\n是否保存上述匿名内容？", "预览诊断导出", MessageBoxButton.YesNo, MessageBoxImage.Information) != MessageBoxResult.Yes) return;
        var dialog = new SaveFileDialog { Filter = "文本文件|*.txt", FileName = "校园网匿名诊断.txt" };
        if (dialog.ShowDialog() == true) File.WriteAllText(dialog.FileName, text);
    }
}
