using System;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using FnOSManager.Services;

namespace FnOSManager
{
    public partial class MainWindow : Window
    {
        private readonly VMManager _vm = VMManager.Shared;
        private readonly SystemMetricsService _metrics = SystemMetricsService.Shared;
        private readonly System.Windows.Threading.DispatcherTimer _uiTimer;

        public MainWindow()
        {
            InitializeComponent();

            _vm.StatusChanged += OnStatusChanged;
            _metrics.MetricsUpdated += OnMetricsUpdated;
            UpdateCheckerService.Shared.StatusChanged += () => Dispatcher.Invoke(UpdateUI);

            _uiTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _uiTimer.Tick += (s, e) =>
            {
                if (_vm.Status == VMStatus.Starting || _vm.Status == VMStatus.Installing)
                {
                    BootTimerText.Text = string.Format("{0:D2}:{1:D2}", _vm.BootingElapsedSeconds / 60, _vm.BootingElapsedSeconds % 60);
                }
            };
            _uiTimer.Start();

            // 启动时后台静默检查更新 (带 12 小时节流)
            _ = UpdateCheckerService.Shared.CheckInBackgroundOnLaunchAsync();

            UpdateUI();
        }

        private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed)
            {
                DragMove();
            }
        }

        private void Close_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }

        private void Minimize_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private async void StartStop_Click(object sender, RoutedEventArgs e)
        {
            if (_vm.Status == VMStatus.Running)
            {
                await _vm.StopVMAsync();
            }
            else
            {
                await _vm.StartVMAsync();
            }
        }

        private async void Reset_Click(object sender, RoutedEventArgs e)
        {
            var res = MessageBox.Show(
                "确定要重置虚拟系统吗？这将会清空虚拟磁盘并重新执行初始化安装向导。",
                "确认重置",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning
            );
            if (res == MessageBoxResult.Yes)
            {
                await _vm.ResetVMAsync();
            }
        }

        private void OpenConsole_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                var domain = $"http://{_vm.Settings.CustomDomainPrefix}.fnos";
                Process.Start(new ProcessStartInfo(domain) { UseShellExecute = true });
            }
            catch { }
        }

        private async void CopyAddress_Click(object sender, MouseButtonEventArgs e)
        {
            try
            {
                var addr = !string.IsNullOrEmpty(_vm.CurrentIP)
                    ? $"http://{_vm.CurrentIP}:{_vm.Settings.WebPort}"
                    : $"http://{_vm.Settings.CustomDomainPrefix}.fnos";
                Clipboard.SetText(addr);
                CopyAddressText.Text = "✓ 已复制";
                await Task.Delay(1500);
                CopyAddressText.Text = "📋 复制";
            }
            catch { }
        }

        private void Subtitle_Click(object sender, MouseButtonEventArgs e)
        {
            if (_vm.Status == VMStatus.Running)
            {
                CopyAddress_Click(sender, e);
            }
        }

        private void VisitOfficial_Click(object sender, MouseButtonEventArgs e)
        {
            try
            {
                Process.Start(new ProcessStartInfo("https://fnnas.com") { UseShellExecute = true });
            }
            catch { }
        }

        private void Logs_Click(object sender, RoutedEventArgs e)
        {
            var logWin = new LogsWindow();
            logWin.Owner = this;
            logWin.ShowDialog();
        }

        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            var settingsWin = new SettingsWindow();
            settingsWin.Owner = this;
            settingsWin.ShowDialog();
        }

        private void OnStatusChanged()
        {
            Dispatcher.Invoke(UpdateUI);
        }

        private void OnMetricsUpdated()
        {
            Dispatcher.Invoke(() =>
            {
                CPUValueText.Text = $"{_metrics.CPUUsagePercent}%";
                CPUProgress.Value = _metrics.CPUUsagePercent;
                CPUSubText.Text = _metrics.CPUStatusText;

                MemValueText.Text = $"{_metrics.MemoryUsedGB:F1} GB";
                MemProgress.Value = Math.Min(100, (_metrics.MemoryUsedGB / _metrics.MemoryQuotaGB) * 100);
                MemSubText.Text = _metrics.MemoryStatusText;

                DiskValueText.Text = $"{_metrics.DiskUsedGB:F1} GB";
                DiskProgress.Value = Math.Min(100, (_metrics.DiskUsedGB / _metrics.DiskTotalGB) * 100);
                DiskSubText.Text = _metrics.DiskStatusText;

                NetValueText.Text = _metrics.NetworkSpeedText;
                NetProgress.Value = _metrics.NetworkRatio * 100;
                NetSubText.Text = _metrics.NetworkSpeedSubText;

                UptimeText.Text = _metrics.UptimeFormatted;
            });
        }

        private void UpdateUI()
        {
            UpdateBadgeDot.Visibility = UpdateCheckerService.Shared.HasNewVersionBadge ? Visibility.Visible : Visibility.Collapsed;
            StatusTitle.Text = _vm.StatusText;
            switch (_vm.Status)
            {
                case VMStatus.Running:
                    StatusDot.Visibility = Visibility.Visible;
                    SpinningRing.Visibility = Visibility.Collapsed;
                    BootTimerBadge.Visibility = Visibility.Collapsed;
                    CopyAddressBadge.Visibility = Visibility.Visible;
                    StatusDot.Fill = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
                    StatusSubtitle.Text = $"{_vm.Settings.CustomDomainPrefix}.fnos · {_vm.CurrentIP}";
                    MainActionButton.Content = "■ 停止系统";
                    MainActionButton.Background = new SolidColorBrush(Color.FromRgb(0xEF, 0x44, 0x44));
                    MainActionButton.IsEnabled = true;
                    ResetButton.IsEnabled = true;
                    ResetButton.Opacity = 1.0;
                    ConsolePillBtn.IsEnabled = true;
                    ConsolePillBtn.Opacity = 1.0;
                    FooterStatus.Text = "⚡ 系统运行中";
                    break;
                case VMStatus.Starting:
                case VMStatus.Installing:
                    StatusDot.Visibility = Visibility.Collapsed;
                    SpinningRing.Visibility = Visibility.Visible;
                    BootTimerBadge.Visibility = Visibility.Visible;
                    CopyAddressBadge.Visibility = Visibility.Collapsed;
                    BootTimerText.Text = string.Format("{0:D2}:{1:D2}", _vm.BootingElapsedSeconds / 60, _vm.BootingElapsedSeconds % 60);
                    StatusSubtitle.Text = _vm.LatestLogLine;
                    MainActionButton.Content = _vm.Status == VMStatus.Installing ? "⏳ 安装引导中..." : "⏳ 启动中...";
                    MainActionButton.Background = new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
                    MainActionButton.IsEnabled = false;
                    ResetButton.IsEnabled = false;
                    ResetButton.Opacity = 0.5;
                    ConsolePillBtn.IsEnabled = false;
                    ConsolePillBtn.Opacity = 0.4;
                    FooterStatus.Text = "⚡ 正在引导";
                    break;
                case VMStatus.Stopping:
                    StatusDot.Visibility = Visibility.Collapsed;
                    SpinningRing.Visibility = Visibility.Visible;
                    BootTimerBadge.Visibility = Visibility.Collapsed;
                    CopyAddressBadge.Visibility = Visibility.Collapsed;
                    StatusSubtitle.Text = "正在释放资源并关闭...";
                    MainActionButton.Content = "⏳ 正在关机...";
                    MainActionButton.Background = new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
                    MainActionButton.IsEnabled = false;
                    ResetButton.IsEnabled = false;
                    ResetButton.Opacity = 0.5;
                    ConsolePillBtn.IsEnabled = false;
                    ConsolePillBtn.Opacity = 0.4;
                    FooterStatus.Text = "⚡ 正在关机";
                    break;
                default:
                    StatusDot.Visibility = Visibility.Visible;
                    SpinningRing.Visibility = Visibility.Collapsed;
                    BootTimerBadge.Visibility = Visibility.Collapsed;
                    CopyAddressBadge.Visibility = Visibility.Collapsed;
                    StatusDot.Fill = new SolidColorBrush(Color.FromRgb(0x6B, 0x72, 0x80));
                    StatusSubtitle.Text = "就绪 · 点击启动";
                    MainActionButton.Content = "▶ 启动系统";
                    MainActionButton.Background = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
                    MainActionButton.IsEnabled = true;
                    ResetButton.IsEnabled = true;
                    ResetButton.Opacity = 1.0;
                    ConsolePillBtn.IsEnabled = false;
                    ConsolePillBtn.Opacity = 0.4;
                    FooterStatus.Text = "⚡ 待命就绪";
                    break;
            }
        }
    }
}
