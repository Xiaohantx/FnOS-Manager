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

                Toggle("挂载 ISO 安装镜像", isOn: $attachISO)
                Toggle("标记为已安装系统", isOn: $isInstalled)
                Text("首次安装时请勾选挂载 ISO；系统安装完成后，可取消勾选 ISO 以便直接从硬盘引导。")
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
        vmManager.updateSettings(s)
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
