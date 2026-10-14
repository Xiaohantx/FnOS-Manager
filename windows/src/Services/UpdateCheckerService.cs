using System;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace FnOSManager.Services
{
    public class UpdateInfo
    {
        public string LatestVersion { get; set; } = "1.0.3";
        public bool HasUpdate { get; set; } = false;
        public string ReleaseUrl { get; set; } = "https://github.com/Xiaohantx/FnOS-Manager/releases";
    }

    public class UpdateCheckerService
    {
        public static readonly UpdateCheckerService Shared = new();
        public const string CurrentVersion = "1.0.4";

        public bool IsChecking { get; private set; } = false;
        public UpdateInfo? CurrentUpdateInfo { get; private set; }
        public string CheckMessage { get; private set; } = "检查更新";
        public bool HasNewVersionBadge { get; private set; } = false;

        public event Action? StatusChanged;

        private static readonly string TimestampFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "fnos_vm", "last_update_check.txt");
        private const double CheckIntervalHours = 12.0;

        private UpdateCheckerService() { }

        public async Task CheckInBackgroundOnLaunchAsync()
        {
            try
            {
                if (File.Exists(TimestampFile))
                {
                    var text = await File.ReadAllTextAsync(TimestampFile);
                    if (DateTime.TryParse(text, out var lastCheck) && (DateTime.UtcNow - lastCheck).TotalHours < CheckIntervalHours)
                    {
                        return;
                    }
                }
            }
            catch { }

            try
            {
                var info = await CheckForUpdatesAsync();
                if (info.HasUpdate)
                {
                    HasNewVersionBadge = true;
                    StatusChanged?.Invoke();
                }

                Directory.CreateDirectory(Path.GetDirectoryName(TimestampFile)!);
                await File.WriteAllTextAsync(TimestampFile, DateTime.UtcNow.ToString("o"));
            }
            catch { }
        }

        public async Task<UpdateInfo> CheckForUpdatesAsync()
        {
            IsChecking = true;
            CheckMessage = "正在检查更新...";
            StatusChanged?.Invoke();

            var result = new UpdateInfo();

            // 1. 尝试 GitHub REST API
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
                client.DefaultRequestHeaders.Add("User-Agent", $"FnOSManager/{CurrentVersion}");
                client.DefaultRequestHeaders.Add("Accept", "application/vnd.github.v3+json");

                var jsonStr = await client.GetStringAsync("https://api.github.com/repos/Xiaohantx/FnOS-Manager/releases/latest");
                using var doc = JsonDocument.Parse(jsonStr);
                if (doc.RootElement.TryGetProperty("tag_name", out var tagElem))
                {
                    var tag = tagElem.GetString() ?? "";
                    var cleanTag = tag.TrimStart('v', 'V', ' ').Trim();
                    result.LatestVersion = cleanTag;
                    result.HasUpdate = IsVersionGreater(cleanTag, CurrentVersion);
                    if (doc.RootElement.TryGetProperty("html_url", out var urlElem))
                    {
                        result.ReleaseUrl = urlElem.GetString() ?? result.ReleaseUrl;
                    }

                    CurrentUpdateInfo = result;
                    IsChecking = false;
                    HasNewVersionBadge = result.HasUpdate;
                    CheckMessage = result.HasUpdate ? $"新版本 v{result.LatestVersion}" : "已是最新版本";
                    StatusChanged?.Invoke();
                    return result;
                }
            }
            catch { }

            // 2. 备选方案: 爬取 Releases HTML 页面
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
                client.DefaultRequestHeaders.Add("User-Agent", $"Mozilla/5.0 FnOSManager/{CurrentVersion}");

                var html = await client.GetStringAsync("https://github.com/Xiaohantx/FnOS-Manager/releases");
                var match = Regex.Match(html, @"releases/tag/v?([0-9]+\.[0-9]+\.[0-9]+)");
                if (match.Success)
                {
                    var cleanTag = match.Groups[1].Value;
                    result.LatestVersion = cleanTag;
                    result.HasUpdate = IsVersionGreater(cleanTag, CurrentVersion);
                    result.ReleaseUrl = $"https://github.com/Xiaohantx/FnOS-Manager/releases/tag/v{cleanTag}";

                    CurrentUpdateInfo = result;
                    IsChecking = false;
                    HasNewVersionBadge = result.HasUpdate;
                    CheckMessage = result.HasUpdate ? $"新版本 v{result.LatestVersion}" : "已是最新版本";
                    StatusChanged?.Invoke();
                    return result;
                }
            }
            catch { }

            IsChecking = false;
            CheckMessage = "已是最新版本";
            StatusChanged?.Invoke();
            return result;
        }

        private static bool IsVersionGreater(string v1, string v2)
        {
            var p1 = v1.Split('.');
            var p2 = v2.Split('.');
            var maxLen = Math.Max(p1.Length, p2.Length);
            for (int i = 0; i < maxLen; i++)
            {
                var num1 = i < p1.Length && int.TryParse(p1[i], out var n1) ? n1 : 0;
                var num2 = i < p2.Length && int.TryParse(p2[i], out var n2) ? n2 : 0;
                if (num1 > num2) return true;
                if (num1 < num2) return false;
            }
            return false;
        }
    }
}
