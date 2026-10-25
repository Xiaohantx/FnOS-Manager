import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var vmManager: VMManager
    @State private var cpuCount: Int = 4
    @State private var memorySizeGB: Int = 4
    @State private var diskSizeGB: Int = 64
    @State private var isoPath: String = ""
    @State private var vmDataDirectory: String = ""
    @State private var attachISO: Bool = true
    @State private var isInstalled: Bool = false
    @State private var webPort: Int = 5666
    @State private var lanForwardedPortsText: String = "3000"
    @State private var savedAlert = false

    private let maxCPUs = ProcessInfo.processInfo.activeProcessorCount
    private let totalRamGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

    public var body: some View {
        Form {
            Section(header: Text("硬件资源配置").font(.headline)) {
                HStack {
                    Text("CPU 核心数:")
                    Spacer()
                    Stepper("\(cpuCount) 核", value: $cpuCount, in: 2...max(2, maxCPUs))
                }

                HStack {
                    Text("内存分配:")
                    Spacer()
                    Stepper("\(memorySizeGB) GB", value: $memorySizeGB, in: 2...max(4, totalRamGB - 2))
                }

                HStack {
                    Text("系统虚拟磁盘大小:")
                    Spacer()
                    Stepper("\(diskSizeGB) GB", value: $diskSizeGB, in: 32...512, step: 16)
                }
                Text("基于 APFS 稀疏文件技术，仅在实际写入数据时占用物理硬盘空间。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("存储与镜像路径").font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PE 安装镜像 (.iso) 路径:")
                    HStack {
                        TextField("ISO 路径", text: $isoPath)
                            .textFieldStyle(.roundedBorder)
                        Button("浏览...") {
                            selectISOFile()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("虚拟机数据存放目录:")
                    HStack {
                        TextField("数据目录", text: $vmDataDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button("浏览...") {
                            selectDataDir()
                        }
                    }
                }

                Toggle("新建系统盘时挂载 ISO 安装镜像", isOn: $attachISO)
                Toggle("标记为已安装系统", isOn: $isInstalled)
                Text("已有系统盘时，启动会优先从原有磁盘引导。需要重装时，请使用下方操作并确认格式化。")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button("格式化重装系统…", role: .destructive) {
                    saveChanges()
                    vmManager.startVM(forceInstallMode: true)
                }
                .disabled(vmManager.status != .stopped && vmManager.status != .error)

                Text("重装会清空系统盘 fnos_system.raw；数据盘文件不会被删除。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("网络与端口").font(.headline)) {
                HStack {
                    Text("Web 管理端端口:")
                    Spacer()
                    TextField("5666", value: $webPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("其他局域网应用端口:")
                    TextField("3000, 8080", text: $lanForwardedPortsText)
                        .textFieldStyle(.roundedBorder)
                    Text("逗号分隔。开启局域网访问后，这些端口会转发到虚拟机中的同端口。默认包含 3000。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack {
                    Button("恢复默认配置") {
                        let def = VMSettings.default
                        applySettings(def)
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("保存配置") {
                        saveChanges()
                        savedAlert = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            savedAlert = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if savedAlert {
                    Text("配置已成功保存！(若虚拟机正在运行，需重启后生效)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            applySettings(vmManager.settings)
        }
    }

    private func applySettings(_ s: VMSettings) {
        cpuCount = s.cpuCount
        memorySizeGB = s.memorySizeGB
        diskSizeGB = s.diskSizeGB
        isoPath = s.isoPath
        vmDataDirectory = s.vmDataDirectory
        attachISO = s.attachISO
        isInstalled = s.isInstalled
        webPort = s.webPort
        lanForwardedPortsText = s.lanForwardedPorts.map(String.init).joined(separator: ", ")
    }

    private func saveChanges() {
        var s = vmManager.settings
        s.cpuCount = cpuCount
        s.memorySizeGB = memorySizeGB
        s.diskSizeGB = diskSizeGB
        s.isoPath = isoPath
        s.vmDataDirectory = vmDataDirectory
        s.attachISO = attachISO
        s.isInstalled = isInstalled
        s.webPort = webPort
        s.lanForwardedPorts = parseForwardedPorts(lanForwardedPortsText)
        vmManager.updateSettings(s)
    }

    private func parseForwardedPorts(_ text: String) -> [Int] {
        let separators = CharacterSet(charactersIn: ",，;； \n\t")
        return Array(Set(text.components(separatedBy: separators)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { (1...65535).contains($0) && $0 != webPort }))
            .sorted()
    }

    private func selectISOFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.prompt = "选择 ISO 镜像"

        if panel.runModal() == .OK, let url = panel.url {
            isoPath = url.path
        }
    }

    private func selectDataDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择数据存储目录"

        if panel.runModal() == .OK, let url = panel.url {
            vmDataDirectory = url.path
        }
    }
}
