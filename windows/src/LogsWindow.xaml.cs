using System.Linq;
using System.Windows;
using System.Windows.Input;
using FnOSManager.Services;

namespace FnOSManager
{
    public partial class LogsWindow : Window
    {
        public LogsWindow()
        {
            InitializeComponent();
            LogsList.ItemsSource = VMManager.Shared.Logs;
            if (VMManager.Shared.Logs.Count > 0)
            {
                LogsList.ScrollIntoView(VMManager.Shared.Logs.Last());
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

        private void Copy_Click(object sender, RoutedEventArgs e)
        {
            var text = string.Join("\n", VMManager.Shared.Logs.Select(l => $"[{l.Timestamp}] [{l.Tag}] {l.Message}"));
            Clipboard.SetText(text);
            MessageBox.Show("日志已复制到剪贴板", "提示", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
}
