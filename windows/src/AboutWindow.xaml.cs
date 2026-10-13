using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using FnOSManager.Services;

namespace FnOSManager
{
    public partial class AboutWindow : Window
    {
        private readonly UpdateCheckerService _updateService = UpdateCheckerService.Shared;

        public AboutWindow()
        {
            InitializeComponent();

            _updateService.StatusChanged += OnUpdateStatusChanged;
            Loaded += async (s, e) =>
            {
                if (_updateService.CheckMessage == "检查更新")
                {
                    await _updateService.CheckForUpdatesAsync();
                }
                else
                {
                    OnUpdateStatusChanged();
                }
            };
        }

        private void OnUpdateStatusChanged()
        {
            Dispatcher.Invoke(() =>
            {
                UpdateBtnText.Text = _updateService.CheckMessage;
                if (_updateService.CurrentUpdateInfo?.HasUpdate == true)
                {
                    UpdateBtnText.Foreground = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
                    CheckUpdateBtn.BorderBrush = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
                }
                else
                {
                    UpdateBtnText.Foreground = new SolidColorBrush(Color.FromRgb(0x94, 0xA3, 0xB8));
                    CheckUpdateBtn.BorderBrush = new SolidColorBrush(Color.FromRgb(0x33, 0x41, 0x55));
                }
            });
        }

        private async void CheckUpdate_Click(object sender, RoutedEventArgs e)
        {
            if (_updateService.CurrentUpdateInfo?.HasUpdate == true)
            {
                try
                {
                    Process.Start(new ProcessStartInfo(_updateService.CurrentUpdateInfo.ReleaseUrl) { UseShellExecute = true });
                }
                catch { }
            }
            else
            {
                await _updateService.CheckForUpdatesAsync();
            }
        }

        private void Header_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed) DragMove();
        }

        private void Close_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }

        private void VisitOfficial_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Process.Start(new ProcessStartInfo("https://fnnas.com") { UseShellExecute = true });
            }
            catch { }
        }

        private void VisitGitHub_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Process.Start(new ProcessStartInfo("https://github.com/Xiaohantx/FnOS-Manager") { UseShellExecute = true });
            }
            catch { }
        }
    }
}
