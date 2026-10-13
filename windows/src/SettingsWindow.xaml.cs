using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Input;
using FnOSManager.Models;
using FnOSManager.Services;
using Microsoft.Win32;

namespace FnOSManager
{
    public partial class SettingsWindow : Window
    {
        private readonly VMSettings _settings = VMManager.Shared.Settings;
        private readonly ISOFetcherService _isoService = ISOFetcherService.Shared;

        public SettingsWindow()
        {
            InitializeComponent();
            LoadValues();
        }

        private async void LoadValues()
        {
            StoragePathText.Text = _settings.DataStorageDirectory;
            DomainCheck.IsChecked = _settings.IsCustomDomainEnabled;

            if (_settings.DataDiskSizeGB == 128) Disk128.IsChecked = true;
            else if (_settings.DataDiskSizeGB == 512) Disk512.IsChecked = true;
            else if (_settings.DataDiskSizeGB >= 1024) Disk1024.IsChecked = true;
            else Disk256.IsChecked = true;

            var iso = await _isoService.FetchLatestISOAsync();
            ISONameText.Text = iso.Name;
            ISOArchBadge.Text = iso.Architecture.ToUpper();
            ISOHashText.Text = $"MD5: {iso.MD5}";

            if (_isoService.HasBuiltInISO(_settings.VMDataDirectory))
            {
                DownloadISOButton.Content = "重新检查/更新镜像";
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

        private void BrowseStorageDir_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Title = "选择飞牛 fnOS 数据存储目录所在文件夹或任意文件 (支持外置硬盘)",
                CheckFileExists = false,
                FileName = "选择此文件夹"
            };
            if (dialog.ShowDialog() == true)
            {
                StoragePathText.Text = Path.GetDirectoryName(dialog.FileName) ?? dialog.FileName;
            }
        }

        private void BrowseISO_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Title = "选择飞牛安装镜像 ISO",
                Filter = "ISO 光盘镜像 (*.iso)|*.iso|所有文件 (*.*)|*.*"
            };
            if (dialog.ShowDialog() == true)
            {
                _settings.ISOPath = dialog.FileName;
                MessageBox.Show($"已绑定自定义镜像: {Path.GetFileName(dialog.FileName)}", "提示", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private async void DownloadISO_Click(object sender, RoutedEventArgs e)
        {
            var targetPath = _isoService.GetBuiltInISOPath(_settings.VMDataDirectory);
            DownloadBar.Visibility = Visibility.Visible;
            DownloadISOButton.IsEnabled = false;

            _isoService.ProgressChanged += () =>
            {
                Dispatcher.Invoke(() =>
                {
                    DownloadBar.Value = _isoService.DownloadProgress * 100;
                });
            };

            await _isoService.StartDownloadAsync(targetPath);

            DownloadISOButton.IsEnabled = true;
            DownloadBar.Visibility = Visibility.Collapsed;
            if (_isoService.ErrorMessage == null)
            {
                MessageBox.Show("官方镜像下载完成，并已自动绑定！", "成功", MessageBoxButton.OK, MessageBoxImage.Information);
                _settings.ISOPath = targetPath;
            }
            else
            {
                MessageBox.Show($"下载失败: {_isoService.ErrorMessage}", "错误", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void About_Click(object sender, RoutedEventArgs e)
        {
            var about = new AboutWindow { Owner = this };
            about.ShowDialog();
        }

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            _settings.DataStorageDirectory = StoragePathText.Text;
            _settings.IsCustomDomainEnabled = DomainCheck.IsChecked ?? true;

            if (Disk128.IsChecked == true) _settings.DataDiskSizeGB = 128;
            else if (Disk512.IsChecked == true) _settings.DataDiskSizeGB = 512;
            else if (Disk1024.IsChecked == true) _settings.DataDiskSizeGB = 1024;
            else _settings.DataDiskSizeGB = 256;

            _settings.Save();
            Close();
        }
    }
}
