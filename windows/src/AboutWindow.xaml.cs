using System.Diagnostics;
using System.Windows;
using System.Windows.Input;

namespace FnOSManager
{
    public partial class AboutWindow : Window
    {
        public AboutWindow()
        {
            InitializeComponent();
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
