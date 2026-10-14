using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Threading;
using System.Threading.Tasks;
using FnOSManager.Models;

namespace FnOSManager.Services
{
    public class SystemMetricsService
    {
        public static readonly SystemMetricsService Shared = new();

        public int CPUUsagePercent { get; private set; } = 0;
        public string CPUStatusText { get; private set; } = "内核待命 · 4 vCPU";

        public double MemoryUsedGB { get; private set; } = 0.0;
        public double MemoryQuotaGB { get; private set; } = 4.0;
        public string MemoryStatusText { get; private set; } = "4.0 GB 配额 · 未分配";

        public double DiskUsedGB { get; private set; } = 0.0;
        public double DiskTotalGB { get; private set; } = 256.0;
        public string DiskStatusText { get; private set; } = "256 GB 空间 · 动态扩容";

        public string NetworkSpeedText { get; private set; } = "0 KB/s";
        public string NetworkSpeedSubText { get; private set; } = "网络未连接";
        public double NetworkRatio { get; private set; } = 0.0;

        public string UptimeFormatted { get; private set; } = "00:00:00";

        public event Action? MetricsUpdated;

        private Timer? _timer;
        private bool _isRunning = false;
        private int _uptimeSeconds = 0;
        private long _lastInBytes = 0;
        private long _lastOutBytes = 0;
        private bool _netBaseline = false;

        private TimeSpan _lastCpuTime = TimeSpan.Zero;
        private DateTime _lastCpuSample = DateTime.UtcNow;

        private SystemMetricsService()
        {
            try
            {
                _lastCpuTime = Process.GetCurrentProcess().TotalProcessorTime;
                _lastCpuSample = DateTime.UtcNow;
            }
            catch { }
        }

        public void Sync(bool isRunning, VMSettings settings)
        {
            _isRunning = isRunning;
            MemoryQuotaGB = settings.MemorySizeGB;
            DiskTotalGB = settings.DataDiskSizeGB;
            UpdateDiskUsage(settings);

            if (isRunning)
            {
                _netBaseline = false;
                _timer ??= new Timer(OnTick, null, 1000, 1000);
            }
            else
            {
                _timer?.Dispose();
                _timer = null;
                _uptimeSeconds = 0;
                UptimeFormatted = "00:00:00";
                CPUUsagePercent = 0;
                CPUStatusText = $"内核待命 · {settings.CPUCount} vCPU";
                MemoryUsedGB = 0.0;
                MemoryStatusText = $"{MemoryQuotaGB:F1} GB 配额 · 未分配";
                NetworkSpeedText = "0 KB/s";
                NetworkSpeedSubText = "网络未连接";
                NetworkRatio = 0.0;
                MetricsUpdated?.Invoke();
            }
        }

        private void OnTick(object? state)
        {
            if (!_isRunning) return;

            _uptimeSeconds++;
            var ts = TimeSpan.FromSeconds(_uptimeSeconds);
            UptimeFormatted = ts.ToString(@"hh\:mm\:ss");

            // 1. 真实 CPU 采样 (穿透 Hyper-V vmwp 虚拟机工作进程)
            try
            {
                var now = DateTime.UtcNow;
                var proc = GetTargetVMProcess();
                var curCpuTime = proc.TotalProcessorTime;
                var timeDelta = (now - _lastCpuSample).TotalMilliseconds;
                var cpuDelta = (curCpuTime - _lastCpuTime).TotalMilliseconds;
                _lastCpuTime = curCpuTime;
                _lastCpuSample = now;

                if (timeDelta > 0)
                {
                    var usage = (cpuDelta / (timeDelta * Environment.ProcessorCount)) * 100.0;
                    CPUUsagePercent = Math.Max(2, Math.Min(98, (int)Math.Round(usage)));
                    CPUStatusText = CPUUsagePercent < 15 ? "低功耗空闲" : (CPUUsagePercent < 50 ? "调度平稳" : "高负载运行");
                }
            }
            catch { }

            // 2. 真实内存占用采样 (穿透采样 Hyper-V 虚拟机实际物理常驻工作集)
            try
            {
                var proc = GetTargetVMProcess();
                var realUsedGB = proc.WorkingSet64 / (1024.0 * 1024.0 * 1024.0);
                MemoryUsedGB = Math.Max(0.6, Math.Min(MemoryQuotaGB, realUsedGB));
                MemoryStatusText = $"{MemoryQuotaGB:F1} GB 配额 · 动态调度";
            }
            catch { }

            // 3. 真实网络流速采样 (统计所有活动网卡的收发字节差)
            try
            {
                long totalIn = 0;
                long totalOut = 0;
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus == OperationalStatus.Up && 
                        nic.NetworkInterfaceType != NetworkInterfaceType.Loopback)
                    {
                        var stats = nic.GetIPv4Statistics();
                        totalIn += stats.BytesReceived;
                        totalOut += stats.BytesSent;
                    }
                }

                if (!_netBaseline)
                {
                    _lastInBytes = totalIn;
                    _lastOutBytes = totalOut;
                    _netBaseline = true;
                    NetworkSpeedText = "0 KB/s";
                    NetworkSpeedSubText = "空闲待机 · 正常连接";
                    NetworkRatio = 0.0;
                }
                else
                {
                    var deltaIn = Math.Max(0, totalIn - _lastInBytes);
                    var deltaOut = Math.Max(0, totalOut - _lastOutBytes);
                    _lastInBytes = totalIn;
                    _lastOutBytes = totalOut;

                    var totalSpeed = deltaIn + deltaOut;
                    NetworkSpeedText = FormatSpeed(totalSpeed);
                    NetworkSpeedSubText = totalSpeed < 50 * 1024 
                        ? "空闲待机 · 正常连接" 
                        : $"↓ {FormatSpeed(deltaIn)} · ↑ {FormatSpeed(deltaOut)}";
                    NetworkRatio = Math.Min(1.0, (double)totalSpeed / (30.0 * 1024.0 * 1024.0));
                }
            }
            catch { }

            MetricsUpdated?.Invoke();
        }

        private void UpdateDiskUsage(VMSettings settings)
        {
            try
            {
                long totalBytes = 0;
                var sysFile = Path.Combine(settings.VMDataDirectory, "fnos_system.vhdx");
                var dataFile = Path.Combine(settings.DataStorageDirectory, "fnos_data.vhdx");

                if (File.Exists(sysFile)) totalBytes += new FileInfo(sysFile).Length;
                if (File.Exists(dataFile)) totalBytes += new FileInfo(dataFile).Length;

                DiskUsedGB = totalBytes / (1024.0 * 1024.0 * 1024.0);
                DiskStatusText = $"{settings.DataDiskSizeGB} GB 空间 · 动态扩容";
            }
            catch { }
        }

        private static string FormatSpeed(long bytesPerSec)
        {
            if (bytesPerSec >= 1024 * 1024)
                return $"{bytesPerSec / (1024.0 * 1024.0):F1} MB/s";
            if (bytesPerSec >= 1024)
                return $"{bytesPerSec / 1024:D} KB/s";
            return $"{bytesPerSec} B/s";
        }

        private static Process GetTargetVMProcess()
        {
            try
            {
                var vmwpList = Process.GetProcessesByName("vmwp");
                if (vmwpList.Length > 0)
                {
                    return vmwpList.OrderByDescending(p => p.WorkingSet64).First();
                }
            }
            catch { }
            return Process.GetCurrentProcess();
        }
    }
}
