using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using FnOSManager.Models;

namespace FnOSManager.Services
{
    public enum VMStatus
    {
        Stopped,
        Starting,
        Installing,
        Running,
        Stopping,
        Error
    }

    public class VMLogEntry
    {
        public string Timestamp { get; set; } = DateTime.Now.ToString("HH:mm:ss");
        public string Tag { get; set; } = "ENGINE";
        public string Message { get; set; } = "";
    }

    public class VMManager
    {
        public static readonly VMManager Shared = new();

        public VMStatus Status { get; private set; } = VMStatus.Stopped;
        public string StatusText => Status switch
        {
            VMStatus.Stopped => "虚拟系统未启动",
            VMStatus.Starting => "正在启动服务...",
            VMStatus.Installing => "UEFI 安装引导中...",
            VMStatus.Running => "虚拟系统运行中",
            VMStatus.Stopping => "正在停止服务...",
            _ => "异常"
        };

        public string CurrentIP { get; private set; } = "192.168.64.2";
        public VMSettings Settings { get; private set; } = VMSettings.Load();
        public ObservableCollection<VMLogEntry> Logs { get; } = new();

        public event Action? StatusChanged;

        private const string VMName = "fnOS-Desktop";

        private VMManager()
        {
            AddLog("ENGINE", "FnOS Manager for Windows 虚拟化引擎已就绪");
        }

        public void AddLog(string tag, string message)
        {
            App.Current?.Dispatcher?.Invoke(() =>
            {
                Logs.Add(new VMLogEntry { Tag = tag, Message = message });
                while (Logs.Count > 500) Logs.RemoveAt(0);
            });
        }

        public async Task StartVMAsync()
        {
            if (Status == VMStatus.Running || Status == VMStatus.Starting) return;

            SetStatus(VMStatus.Starting);
            AddLog("ENGINE", "收到启动指令，正在初始化 Windows 虚拟化环境...");

            await Task.Run(() =>
            {
                try
                {
                    // 1. 确保存储目录就绪
                    Directory.CreateDirectory(Settings.VMDataDirectory);
                    Directory.CreateDirectory(Settings.DataStorageDirectory);

                    var sysDisk = Path.Combine(Settings.VMDataDirectory, "fnos_system.vhdx");
                    var dataDisk = Path.Combine(Settings.DataStorageDirectory, "fnos_data.vhdx");

                    bool isFirstInstall = !File.Exists(sysDisk);

                    // 2. 检查或下载系统安装镜像
                    var isoService = ISOFetcherService.Shared;
                    var builtInISO = isoService.GetBuiltInISOPath(Settings.VMDataDirectory);

                    if (isFirstInstall && !File.Exists(builtInISO) && string.IsNullOrEmpty(Settings.ISOPath))
                    {
                        AddLog("ISO", $"检测到首次部署，正在获取官方 {isoService.CurrentISO.Architecture} 安装镜像...");
                        SetStatus(VMStatus.Installing);
                        isoService.StartDownloadAsync(builtInISO).Wait();
                        Settings.ISOPath = builtInISO;
                        Settings.Save();
                    }

                    var activeISO = File.Exists(Settings.ISOPath) ? Settings.ISOPath : builtInISO;

                    // 3. 执行 PowerShell 配置 Hyper-V 实例
                    AddLog("HW", $"分配硬件资源: {Settings.CPUCount} 核 CPU / {Settings.MemorySizeGB} GB 内存 / 动态内存回收已开启");
                    
                    var psScript = $@"
                        $vmName = '{VMName}'
                        $sysDisk = '{sysDisk}'
                        $dataDisk = '{dataDisk}'
                        $isoPath = '{activeISO}'

                        # 创建动态扩展虚拟硬盘
                        if (!(Test-Path $sysDisk)) {{
                            New-VHD -Path $sysDisk -SizeBytes 64GB -Dynamic | Out-Null
                        }}
                        if (!(Test-Path $dataDisk)) {{
                            New-VHD -Path $dataDisk -SizeBytes {Settings.DataDiskSizeGB}GB -Dynamic | Out-Null
                        }}

                        # 移除已有旧实例
                        if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {{
                            Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
                        }}

                        # 创建 Generation 2 UEFI 虚拟机
                        $vm = New-VM -Name $vmName -Generation 2 -MemoryStartupBytes {Settings.MemorySizeGB}GB -SwitchName 'Default Switch'
                        Set-VMProcessor -VMName $vmName -Count {Settings.CPUCount}
                        Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $true

                        # 挂载磁盘与 ISO 光驱
                        Add-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $sysDisk
                        Add-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $dataDisk
                        if (Test-Path $isoPath) {{
                            Add-VMDvdDrive -VMName $vmName -ControllerNumber 0 -ControllerLocation 2 -Path $isoPath
                            $dvd = Get-VMDvdDrive -VMName $vmName
                            Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd
                        }}

                        Start-VM -Name $vmName
                    ";

                    RunPowerShell(psScript);

                    AddLog("BOOT", "Windows Hyper-V 实例已拉起，正在引导 fnOS 内核服务...");

                    // 4. 等待网络与控制台响应
                    Task.Delay(3000).Wait();
                    CurrentIP = DetectVMIP() ?? "192.168.64.2";
                    AddLog("NET", $"侦测到虚拟机局域网地址: {CurrentIP}，绑定本地域名 nas.fnos...");

                    if (Settings.IsCustomDomainEnabled)
                    {
                        HostsManager.Shared.UpdateHosts(Settings.CustomDomainPrefix, CurrentIP);
                    }

                    SetStatus(VMStatus.Running);
                    AddLog("READY", $"虚拟系统启动完成，访问地址: http://{Settings.CustomDomainPrefix}.fnos · {CurrentIP}");
                    SystemMetricsService.Shared.Sync(true, Settings);
                }
                catch (Exception ex)
                {
                    AddLog("ERROR", $"启动异常: {ex.Message}");
                    SetStatus(VMStatus.Error);
                }
            });
        }

        public async Task StopVMAsync()
        {
            if (Status == VMStatus.Stopped) return;

            SetStatus(VMStatus.Stopping);
            AddLog("ENGINE", "正在优雅关闭虚拟机实例...");

            await Task.Run(() =>
            {
                try
                {
                    RunPowerShell($"Stop-VM -Name '{VMName}' -Force -ErrorAction SilentlyContinue");
                    AddLog("ENGINE", "虚拟化实例已安全停止");
                }
                catch { }

                SetStatus(VMStatus.Stopped);
                SystemMetricsService.Shared.Sync(false, Settings);
            });
        }

        public async Task ResetVMAsync()
        {
            await StopVMAsync();
            AddLog("RESET", "正在重置虚拟机并清空虚拟磁盘...");
            try
            {
                var sysDisk = Path.Combine(Settings.VMDataDirectory, "fnos_system.vhdx");
                var dataDisk = Path.Combine(Settings.DataStorageDirectory, "fnos_data.vhdx");
                if (File.Exists(sysDisk)) File.Delete(sysDisk);
                if (File.Exists(dataDisk)) File.Delete(dataDisk);
                AddLog("RESET", "虚拟磁盘已清空，准备重新启动全新系统...");
            }
            catch (Exception ex)
            {
                AddLog("ERROR", $"清理失败: {ex.Message}");
            }
            await StartVMAsync();
        }

        private void SetStatus(VMStatus status)
        {
            Status = status;
            App.Current?.Dispatcher?.Invoke(() => StatusChanged?.Invoke());
        }

        private static void RunPowerShell(string script)
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{script}\"",
                CreateNoWindow = true,
                UseShellExecute = false
            };
            using var proc = Process.Start(psi);
            proc?.WaitForExit(30000);
        }

        private string? DetectVMIP()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoProfile -Command \"(Get-VMNetworkAdapter -VMName '{VMName}').IPAddresses[0]\"",
                    RedirectStandardOutput = true,
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                using var proc = Process.Start(psi);
                var ip = proc?.StandardOutput.ReadToEnd().Trim();
                if (!string.IsNullOrEmpty(ip) && ip.Contains(".")) return ip;
            }
            catch { }
            return null;
        }
    }
}
