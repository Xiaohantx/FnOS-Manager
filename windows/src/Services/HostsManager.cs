using System;
using System.IO;
using System.Linq;
using Microsoft.Win32;

namespace FnOSManager.Services
{
    public class HostsManager
    {
        public static readonly HostsManager Shared = new();

        private static string HostsPath => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "drivers", "etc", "hosts"
        );

        public void UpdateHosts(string prefix, string ip)
        {
            try
            {
                var domain = $"{prefix}.fnos";
                if (!File.Exists(HostsPath)) return;

                var lines = File.ReadAllLines(HostsPath).ToList();
                lines.RemoveAll(l => l.Contains(".fnos"));

                lines.Add($"{ip,-15} {domain}");
                lines.Add($"{ip,-15} fnos.local");

                File.WriteAllLines(HostsPath, lines);
                EnsureProxyBypass();
            }
            catch { }
        }

        public void RemoveHosts()
        {
            try
            {
                if (!File.Exists(HostsPath)) return;
                var lines = File.ReadAllLines(HostsPath).ToList();
                lines.RemoveAll(l => l.Contains(".fnos"));
                File.WriteAllLines(HostsPath, lines);
            }
            catch { }
        }

        public void EnsureProxyBypass()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings", true);
                if (key != null)
                {
                    var overrideVal = key.GetValue("ProxyOverride") as string ?? "<local>";
                    if (!overrideVal.Contains("*.fnos"))
                    {
                        var updated = overrideVal.TrimEnd(';') + ";*.fnos;nas.fnos;<local>";
                        key.SetValue("ProxyOverride", updated);
                    }
                }
            }
            catch { }
        }
    }
}
