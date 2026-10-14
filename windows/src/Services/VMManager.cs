using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
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
            VMStatus.Stopping => "正在释放资源...",
            _ => "异常"
        };

        public string LatestLogLine { get; private set; } = "就绪 · 点击启动";
        public int BootingElapsedSeconds { get; private set; } = 0;
        public string CurrentIP { get; private set; } = "192.168.64.2";
        public VMSettings Settings { get; private set; } = VMSettings.Load();
        public ObservableCollection<VMLogEntry> Logs { get; } = new();

        public event Action? StatusChanged;

        private const string VMName = "fnOS-Desktop";
        private System.Threading.Timer? _bootTimer;

        private VMManager()
        {
            AddLog("ENGINE", "FnOS Manager for Windows 虚拟化引擎已就绪");
        }

        public void AddLog(string tag, string message)
        {
            LatestLogLine = message;
            void Add()
            {
                Logs.Add(new VMLogEntry { Tag = tag, Message = message });
                while (Logs.Count > 500) Logs.RemoveAt(0);
            }

            if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
            {
                Application.Current.Dispatcher.Invoke(Add);
            }
            else
            {
                Add();
            }
        }

        public async Task StartVMAsync()
        {
            if (Status == VMStatus.Running || Status == VMStatus.Starting || Status == VMStatus.Installing) return;

            AddLog("ENGINE", "收到启动指令，正在初始化 Windows 虚拟化环境...");

            // 0. 存储健康与外置移动硬盘预检
            var health = CheckStorageHealth(Settings.DataStorageDirectory);
            if (!health.IsHealthy)
            {
                SetStatus(VMStatus.Error);
                var err = health.ErrorMessage ?? "存储目录异常";
                AddLog("ERROR", $"存储预检未通过: {err}");
                MessageBox.Show(err, "存储健康预检提示", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            // 1. 存储目录与磁盘检查
            Directory.CreateDirectory(Settings.VMDataDirectory);
            Directory.CreateDirectory(Settings.DataStorageDirectory);

            var sysDisk = Path.Combine(Settings.VMDataDirectory, "fnos_system.vhdx");
            var dataDisk = Path.Combine(Settings.DataStorageDirectory, "fnos_data.vhdx");

            bool isFirstInstall = !File.Exists(sysDisk);

            // 2. 镜像检查 (与 Mac 保持严格一致：未内置时引导一键自动下载)
            var isoService = ISOFetcherService.Shared;
            var activeISO = File.Exists(Settings.ISOPath) ? Settings.ISOPath : isoService.GetBuiltInISOPath(Settings.VMDataDirectory);

            if (isFirstInstall && !File.Exists(activeISO))
            {
                SetStatus(VMStatus.Stopped);
                var msg = $"尚未检测到官方系统安装镜像 ({isoService.CurrentISO.Architecture.ToUpper()})。\n\n是否立即一键自动下载官方镜像？下载完成后即可直接启动并安装系统。";
                var res = MessageBox.Show(msg, "获取系统镜像", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (res == MessageBoxResult.Yes)
                {
                    _ = isoService.DownloadOfficialISOAsync(Settings.VMDataDirectory);
                    AddLog("ISO", "已在后台启动官方镜像下载任务，可点击右上角设置查看进度");
                }
                return;
            }

            var shouldAttachISO = isFirstInstall || (Settings.AttachISO && File.Exists(activeISO));
            SetStatus(shouldAttachISO ? VMStatus.Installing : VMStatus.Starting);
            StartBootTimer();

            await Task.Run(() =>
            {
                try
                {
                    // 3. 检查并确保 Hyper-V 运行支持
                    RunPowerShell("Start-Service vmms -ErrorAction SilentlyContinue");
                    if (!CheckHyperVAvailable())
                    {
                        AddLog("WARN", "检测到当前 Windows 尚未启用 Hyper-V 虚拟化功能服务");
                        AddLog("WARN", "若启动失败，请在「启用或关闭 Windows 功能」中勾选 Hyper-V 平台并重启电脑");
                    }

                    // 4. 创建动态扩展虚拟磁盘 (使用 diskpart 原生保障，无需 Hyper-V PowerShell 模块依赖)
                    EnsureVHDX(sysDisk, 64);
                    EnsureVHDX(dataDisk, Settings.DataDiskSizeGB);

                    AddLog("STORAGE", $"已挂载虚拟磁盘: 系统盘 64 GB / 数据盘 {Settings.DataDiskSizeGB} GB (动态按需占用)");
                    AddLog("HW", $"分配硬件资源: {Settings.CPUCount} 核 CPU / {Settings.MemorySizeGB} GB 内存 / 动态内存回收已开启");

                    if (shouldAttachISO)
                    {
                        AddLog("ISO", $"已挂载内置安装镜像 ({Path.GetFileName(activeISO)})，进入安装引导模式");
                    }
                    else
                    {
                        AddLog("STORAGE", "检测到已安装的系统盘，进入常规快速启动模式");
                    }

                    // 5. 编排并拉起 Hyper-V 实例 (禁用 Windows SecureBoot 兼容 Linux 原生引导)
                    var psScript = $@"
                        $vmName = '{VMName}'
                        $sysDisk = '{sysDisk}'
                        $dataDisk = '{dataDisk}'
                        $isoPath = '{activeISO}'
                        $shouldAttachISO = ${(shouldAttachISO ? "true" : "false")}

                        # 清理同名旧实例
                        if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {{
                            Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
                        }}

                        # 查找可用的虚拟网络交换机 (优先 Default Switch，次选任一活动虚拟交换机)
                        $sw = Get-VMSwitch | Where-Object {{ $_.SwitchType -eq 'Internal' -or $_.Name -like '*Default*' -or $_.Name -like '*默认*' }} | Select-Object -First 1
                        if (!$sw) {{ $sw = Get-VMSwitch | Select-Object -First 1 }}

                        # 创建第2代 UEFI 虚拟机
                        if ($sw) {{
                            $vm = New-VM -Name $vmName -Generation 2 -MemoryStartupBytes {Settings.MemorySizeGB}GB -SwitchName $sw.Name
                        }} else {{
                            $vm = New-VM -Name $vmName -Generation 2 -MemoryStartupBytes {Settings.MemorySizeGB}GB
                        }}

                        Set-VMProcessor -VMName $vmName -Count {Settings.CPUCount}
                        Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $true

                        # 挂载磁盘控制器
                        Add-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $sysDisk
                        Add-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -Path $dataDisk

                        # 关键：对 Linux/fnOS 系统必须禁用 Windows Secure Boot，以防 UEFI 引导拦截
                        Set-VMFirmware -VMName $vmName -EnableSecureBoot $false

                        if ($shouldAttachISO -and (Test-Path $isoPath)) {{
                            Add-VMDvdDrive -VMName $vmName -ControllerNumber 0 -ControllerLocation 2 -Path $isoPath
                            $dvd = Get-VMDvdDrive -VMName $vmName
                            Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd
                        }} else {{
                            $hdd = Get-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0
                            Set-VMFirmware -VMName $vmName -FirstBootDevice $hdd
                        }}

                        Start-VM -Name $vmName
                    ";

                    var (exitCode, stdout, stderr) = RunPowerShellWithOutput(psScript);
                    if (exitCode != 0)
                    {
                        throw new Exception(string.IsNullOrWhiteSpace(stderr) ? stdout : stderr);
                    }

                    AddLog("BOOT", "Windows Hyper-V 实例已启动，正在执行 UEFI 引导...");

                    // 6. 探测虚拟机局域网 IP
                    var detectedIP = ProbeVMIP(15);
                    CurrentIP = detectedIP ?? "192.168.64.2";
                    AddLog("NET", $"侦测到虚拟机地址: {CurrentIP}，正在检测 Web 控制台端口 (5666)...");

                    if (Settings.IsCustomDomainEnabled)
                    {
                        HostsManager.Shared.UpdateHosts(Settings.CustomDomainPrefix, CurrentIP);
                    }

                    StopBootTimer();
                    SetStatus(VMStatus.Running);
                    AddLog("READY", $"虚拟系统启动完成，访问地址: http://{Settings.CustomDomainPrefix}.fnos · {CurrentIP}");
                    SystemMetricsService.Shared.Sync(true, Settings);

                    // 若初期未探测到实际 IP，在后台继续平滑侦测并更新 hosts
                    if (detectedIP == null)
                    {
                        _ = Task.Run(() =>
                        {
                            for (int i = 0; i < 45 && Status == VMStatus.Running; i++)
                            {
                                Task.Delay(2000).Wait();
                                var bgIP = ProbeVMIP(1);
                                if (!string.IsNullOrEmpty(bgIP) && bgIP != CurrentIP && !bgIP.StartsWith("169.254"))
                                {
                                    CurrentIP = bgIP;
                                    AddLog("NET", $"已侦测到虚拟机实际分配 IP: {CurrentIP}，更新本地域名映射");
                                    if (Settings.IsCustomDomainEnabled)
                                    {
                                        HostsManager.Shared.UpdateHosts(Settings.CustomDomainPrefix, CurrentIP);
                                    }
                                    Application.Current?.Dispatcher?.Invoke(() => StatusChanged?.Invoke());
                                    break;
                                }
                            }
                        });
                    }
                }
                catch (Exception ex)
                {
                    StopBootTimer();
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

                StopBootTimer();
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
                AddLog("RESET", "虚拟磁盘已清空，即将重新执行无人值守安装...");
            }
            catch (Exception ex)
            {
                AddLog("ERROR", $"清理失败: {ex.Message}");
            }
            await StartVMAsync();
        }

        private void StartBootTimer()
        {
            BootingElapsedSeconds = 0;
            _bootTimer?.Dispose();
            _bootTimer = new System.Threading.Timer(_ =>
            {
                BootingElapsedSeconds++;
                if (BootingElapsedSeconds % 10 == 0 && (Status == VMStatus.Starting || Status == VMStatus.Installing))
                {
                    AddLog("BOOT", $"引导进行中 (已耗时 {BootingElapsedSeconds}s) · 等待网络就绪...");
                }
            }, null, 1000, 1000);
        }

        private void StopBootTimer()
        {
            _bootTimer?.Dispose();
            _bootTimer = null;
        }

        private void SetStatus(VMStatus status)
        {
            Status = status;
            Application.Current?.Dispatcher?.Invoke(() => StatusChanged?.Invoke());
        }

        private static bool CheckHyperVAvailable()
        {
            try
            {
                var (code, outStr, _) = RunPowerShellWithOutput("(Get-Service vmms -ErrorAction SilentlyContinue) -ne $null");
                return outStr.Trim().Equals("True", StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        public static void EnsureVHDX(string path, int sizeGB)
        {
            if (File.Exists(path)) return;
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

            // 优先使用 diskpart.exe，全版本 Windows 10/11 物理机 100% 原生支持
            var scriptPath = Path.Combine(Path.GetTempPath(), $"mk_vhdx_{Guid.NewGuid():N}.txt");
            try
            {
                File.WriteAllText(scriptPath, $"create vdisk file=\"{path}\" maximum={sizeGB * 1024} type=expandable\nexit\n");
                var psi = new ProcessStartInfo("diskpart.exe", $"/s \"{scriptPath}\"")
                {
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                using var p = Process.Start(psi);
                p?.WaitForExit(15000);
            }
            catch { }
            finally
            {
                try { if (File.Exists(scriptPath)) File.Delete(scriptPath); } catch { }
            }
        }

        private static void RunPowerShell(string script)
        {
            RunPowerShellWithOutput(script);
        }

        private static (int exitCode, string stdout, string stderr) RunPowerShellWithOutput(string script)
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{script}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                UseShellExecute = false
            };
            using var proc = Process.Start(psi);
            if (proc == null) return (-1, "", "无法拉起 PowerShell");
            var stdout = proc.StandardOutput.ReadToEnd();
            var stderr = proc.StandardError.ReadToEnd();
            proc.WaitForExit(30000);
            return (proc.ExitCode, stdout, stderr);
        }

        private string? ProbeVMIP(int maxSeconds)
        {
            for (int i = 0; i < maxSeconds; i++)
            {
                // 1. 通过 Hyper-V NetworkAdapter 查询
                var (code, outStr, _) = RunPowerShellWithOutput($"(Get-VMNetworkAdapter -VMName '{VMName}' -ErrorAction SilentlyContinue).IPAddresses[0]");
                var trimmed = outStr.Trim();
                if (!string.IsNullOrEmpty(trimmed) && trimmed.Contains(".") && !trimmed.StartsWith("169.254"))
                {
                    return trimmed;
                }

                // 2. 通过 ARP 表查询
                try
                {
                    var psi = new ProcessStartInfo("arp.exe", "-a")
                    {
                        RedirectStandardOutput = true,
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    using var p = Process.Start(psi);
                    var arpOut = p?.StandardOutput.ReadToEnd() ?? "";
                    p?.WaitForExit(2000);

                    // 匹配 172.x.x.x 或 192.168.x.x
                    var matches = Regex.Matches(arpOut, @"\b(172\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b");
                    foreach (Match m in matches)
                    {
                        var ip = m.Value;
                        if (!ip.EndsWith(".1") && !ip.EndsWith(".255")) return ip;
                    }
                }
                catch { }

                Task.Delay(1000).Wait();
            }
            return null;
        }

        public (bool IsHealthy, string? ErrorMessage) CheckStorageHealth(string path)
        {
            try
            {
                var fullPath = Path.GetFullPath(path);
                var root = Path.GetPathRoot(fullPath);
                if (string.IsNullOrEmpty(root) || !Directory.Exists(root))
                {
                    return (false, "外置存储设备未连接或驱动器离线，请插入后重试");
                }

                var drive = new DriveInfo(root);
                if (!drive.IsReady)
                {
                    return (false, $"存储驱动器 ({root}) 当前不可用或处于保护状态");
                }

                var freeGB = drive.AvailableFreeSpace / (1024.0 * 1024.0 * 1024.0);
                if (freeGB < 3.0)
                {
                    return (false, $"数据驱动器 ({root}) 剩余可用空间不足 (仅剩 {freeGB:F1} GB，需保留至少 3.0 GB)");
                }

                return (true, null);
            }
            catch (Exception ex)
            {
                return (false, $"存储环境检查异常: {ex.Message}");
            }
        }
    }
}
