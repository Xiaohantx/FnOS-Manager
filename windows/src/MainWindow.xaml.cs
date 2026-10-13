using System;
using System.Diagnostics;
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

        public MainWindow()
        {
            InitializeComponent();

            _vm.StatusChanged += OnStatusChanged;
            _metrics.MetricsUpdated += OnMetricsUpdated;

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
            StatusTitle.Text = _vm.StatusText;
            switch (_vm.Status)
            {
                case VMStatus.Running:
                    StatusDot.Fill = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
                    StatusSubtitle.Text = $"nas.fnos · {_vm.CurrentIP}";
                    MainActionButton.Content = "■ 停止系统";
                    MainActionButton.Background = new SolidColorBrush(Color.FromRgb(0xEF, 0x44, 0x44));
                    FooterStatus.Text = "⚡ 系统运行中";
                    break;
                case VMStatus.Starting:
                case VMStatus.Installing:
                    StatusDot.Fill = new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
                    StatusSubtitle.Text = "正在引导服务与网络...";
                    MainActionButton.Content = "⏳ 启动中...";
                    MainActionButton.Background = new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
                    FooterStatus.Text = "⚡ 正在启动";
                    break;
                default:
                    StatusDot.Fill = new SolidColorBrush(Color.FromRgb(0x6B, 0x72, 0x80));
                    StatusSubtitle.Text = "就绪 · 点击启动";
                    MainActionButton.Content = "▶ 启动系统";
                    MainActionButton.Background = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
                    FooterStatus.Text = "⚡ 待命就绪";
                    break;
            }
        }
    }
}
