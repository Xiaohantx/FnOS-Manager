using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace FnOSManager.Models
{
    public class VMSettings
    {
        public int CPUCount { get; set; } = Math.Max(2, Math.Min(8, Environment.ProcessorCount / 2));
        public int MemorySizeGB { get; set; } = 4;
        public int DataDiskSizeGB { get; set; } = 256;
        public string VMDataDirectory { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FnOSManager", "vm_data");
        public string DataStorageDirectory { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FnOSManager", "storage");
        public string ISOPath { get; set; } = "";
        public bool AttachISO { get; set; } = true;
        public string CustomDomainPrefix { get; set; } = "nas";
        public bool IsCustomDomainEnabled { get; set; } = true;
        public bool DynamicOptimization { get; set; } = true;
        public bool AutoStartOnLogin { get; set; } = false;

        public string Architecture => RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.Arm64 => "arm64",
            _ => "x86_64"
        };

        private static string SettingsFilePath => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FnOSManager",
            "settings.json"
        );

        public static VMSettings Load()
        {
            try
            {
                if (File.Exists(SettingsFilePath))
                {
                    var json = File.ReadAllText(SettingsFilePath);
                    var settings = JsonSerializer.Deserialize<VMSettings>(json);
                    if (settings != null) return settings;
                }
            }
            catch { }
            return new VMSettings();
        }

        public void Save()
        {
            try
            {
                var dir = Path.GetDirectoryName(SettingsFilePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(SettingsFilePath, json);
            }
            catch { }
        }
    }
}
