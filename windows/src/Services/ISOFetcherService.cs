using System;
using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace FnOSManager.Services
{
    public class OfficialISOInfo
    {
        public string Name { get; set; } = "";
        public string Url { get; set; } = "";
        public string MD5 { get; set; } = "";
        public string Architecture { get; set; } = "x86_64";
    }

    public class ISOFetcherService
    {
        public static readonly ISOFetcherService Shared = new();

        public OfficialISOInfo CurrentISO { get; private set; }
        public bool IsDownloading { get; private set; }
        public double DownloadProgress { get; private set; }
        public string DownloadSpeedText { get; private set; } = "0 KB/s";
        public string DownloadedText { get; private set; } = "0 MB / 0 MB";
        public string? ErrorMessage { get; private set; }

        public event Action? ProgressChanged;
        public event Action<string>? DownloadCompleted;

        private CancellationTokenSource? _cts;

        public static readonly OfficialISOInfo FallbackX86ISO = new()
        {
            Name = "官方 x86_64 安装镜像 ISO (适用于 Intel / AMD 架构 PC)",
            Url = "https://iso.liveupdate.fnnas.com/x86/iso/fnos_Mainland-PE_x86_1.2.0701_2727.iso",
            MD5 = "7d47c0b90c12080458b288fb774b147d",
            Architecture = "x86_64"
        };

        public static readonly OfficialISOInfo FallbackARM64ISO = new()
        {
            Name = "官方 ARM64 安装镜像 ISO (适用于 Windows on ARM / 骁龙 X Elite)",
            Url = "https://iso.liveupdate.fnnas.com/arm/iso/armsr/fnos_Mainland-PE_arm_1.2.0302_armsr_2301.iso",
            MD5 = "7babaa1bf2405a6880e802904b58a809",
            Architecture = "arm64"
        };

        private ISOFetcherService()
        {
            CurrentISO = RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 
                ? FallbackARM64ISO 
                : FallbackX86ISO;
        }

        public string GetBuiltInISOPath(string baseDir)
        {
            var filename = CurrentISO.Architecture == "arm64" ? "fnos_arm64.iso" : "fnos_x86_64.iso";
            return Path.Combine(baseDir, filename);
        }

        public bool HasBuiltInISO(string baseDir)
        {
            var p = GetBuiltInISOPath(baseDir);
            return File.Exists(p) && new FileInfo(p).Length > 100_000_000;
        }

        public async Task<OfficialISOInfo> FetchLatestISOAsync()
        {
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
                client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) FnOSManager/1.0.2");

                var isArm = RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64;
                var targetPage = isArm ? "https://fnnas.com/download-arm" : "https://fnnas.com/download?key=fnos";
                var html = await client.GetStringAsync(targetPage);

                var isoMatch = Regex.Match(html, @"https?://[a-zA-Z0-9\.\_\:\/\-]+?\.iso");
                var md5Match = Regex.Match(html, @"[a-fA-F0-9]{32}");

                if (isoMatch.Success && md5Match.Success)
                {
                    CurrentISO = new OfficialISOInfo
                    {
                        Name = isArm ? FallbackARM64ISO.Name : FallbackX86ISO.Name,
                        Url = isoMatch.Value,
                        MD5 = md5Match.Value.ToLowerInvariant(),
                        Architecture = isArm ? "arm64" : "x86_64"
                    };
                }
            }
            catch
            {
                CurrentISO = RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? FallbackARM64ISO : FallbackX86ISO;
            }
            return CurrentISO;
        }

        public async Task StartDownloadAsync(string destinationPath)
        {
            if (IsDownloading) return;

            IsDownloading = true;
            DownloadProgress = 0;
            ErrorMessage = null;
            _cts = new CancellationTokenSource();

            var dir = Path.GetDirectoryName(destinationPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            var tempPath = destinationPath + ".downloading";

            try
            {
                using var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
                using var response = await client.GetAsync(CurrentISO.Url, HttpCompletionOption.ResponseHeadersRead, _cts.Token);
                response.EnsureSuccessStatusCode();

                var totalBytes = response.Content.Headers.ContentLength ?? 3_500_000_000L;
                using var stream = await response.Content.ReadAsStreamAsync(_cts.Token);
                using var fs = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None);

                var buffer = new byte[81920];
                long totalRead = 0;
                var startTime = DateTime.UtcNow;
                var lastTime = startTime;
                long lastRead = 0;

                int bytesRead;
                while ((bytesRead = await stream.ReadAsync(buffer, 0, buffer.Length, _cts.Token)) > 0)
                {
                    await fs.WriteAsync(buffer, 0, bytesRead, _cts.Token);
                    totalRead += bytesRead;

                    var now = DateTime.UtcNow;
                    var elapsedSec = (now - lastTime).TotalSeconds;
                    if (elapsedSec >= 0.5)
                    {
                        var speed = (totalRead - lastRead) / elapsedSec;
                        DownloadSpeedText = FormatSpeed(speed);
                        DownloadedText = $"{totalRead / (1024 * 1024):N0} MB / {totalBytes / (1024 * 1024):N0} MB";
                        DownloadProgress = Math.Min(1.0, (double)totalRead / totalBytes);
                        lastTime = now;
                        lastRead = totalRead;
                        ProgressChanged?.Invoke();
                    }
                }

                fs.Close();

                if (File.Exists(destinationPath)) File.Delete(destinationPath);
                File.Move(tempPath, destinationPath);

                IsDownloading = false;
                DownloadProgress = 1.0;
                ProgressChanged?.Invoke();
                DownloadCompleted?.Invoke(destinationPath);
            }
            catch (Exception ex)
            {
                IsDownloading = false;
                ErrorMessage = ex.Message;
                if (File.Exists(tempPath)) try { File.Delete(tempPath); } catch { }
                ProgressChanged?.Invoke();
            }
        }

        public void CancelDownload()
        {
            _cts?.Cancel();
            IsDownloading = false;
            ProgressChanged?.Invoke();
        }

        private static string FormatSpeed(double bytesPerSec)
        {
            if (bytesPerSec >= 1024 * 1024)
                return $"{bytesPerSec / (1024 * 1024):F1} MB/s";
            return $"{bytesPerSec / 1024:F0} KB/s";
        }
    }
}
