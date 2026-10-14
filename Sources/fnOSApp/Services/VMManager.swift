import Foundation
import Virtualization
import Combine

public struct VMLogEntry: Identifiable, Equatable {
    public enum Level: String {
        case info
        case success
        case warning
        case error
    }

    public let id = UUID()
    public let timestamp: String
    public let tag: String
    public let message: String
    public let level: Level

    public init(timestamp: String, tag: String, message: String, level: Level = .info) {
        self.timestamp = timestamp
        self.tag = tag
        self.message = message
        self.level = level
    }
}

@MainActor
public class VMManager: NSObject, ObservableObject {
    public static let shared = VMManager()

    @Published public var status: VMStatus = .stopped
    @Published public var currentIP: String? = nil
    @Published public var isWebUIAvailable: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var settings: VMSettings
    @Published public var vzVirtualMachine: VZVirtualMachine? = nil
    @Published public var consoleLogs: String = ""
    @Published public var logEntries: [VMLogEntry] = []
    @Published public var latestLogLine: String = "就绪 · 等待启动指令"
    @Published public var bootingElapsedSeconds: Int = 0

    private let storageService = StorageService.shared
    private let networkMonitor = NetworkMonitor.shared
    private var targetMAC: VZMACAddress?
    private var consolePipe: Pipe? = nil
    private var bootProgressTimer: Timer? = nil

    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public init(settings: VMSettings = .load()) {
        self.settings = settings
        super.init()
        HostsManager.shared.ensureProxyBypass(domainPrefix: settings.customDomainPrefix)
        addSystemLog("FnOS Manager 虚拟化引擎已就绪", tag: "ENGINE", level: .info)
    }

    public func updateSettings(_ newSettings: VMSettings) {
        self.settings = newSettings
        self.settings.save()
    }

    public func addSystemLog(_ message: String, tag: String = "SYSTEM", level: VMLogEntry.Level = .info) {
        let ts = Self.logTimeFormatter.string(from: Date())
        let cleanMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMsg.isEmpty else { return }

        let entry = VMLogEntry(timestamp: ts, tag: tag, message: cleanMsg, level: level)
        logEntries.append(entry)
        if logEntries.count > 300 {
            logEntries.removeFirst(logEntries.count - 300)
        }
        latestLogLine = cleanMsg

        let formattedLine = "[\(ts)] [\(tag)] \(cleanMsg)\n"
        consoleLogs.append(formattedLine)
        if consoleLogs.count > 24000 {
            consoleLogs = String(consoleLogs.suffix(12000))
        }
    }

    public func clearLogs() {
        logEntries.removeAll()
        consoleLogs = ""
        addSystemLog("日志缓冲区已清空", tag: "SYSTEM", level: .info)
    }

    private func startBootProgressTimer(isInstallMode: Bool) {
        stopBootProgressTimer()
        bootingElapsedSeconds = 0

        bootProgressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.status == .installing || self.status == .starting else {
                    self.stopBootProgressTimer()
                    return
                }
                self.bootingElapsedSeconds += 1
                let sec = self.bootingElapsedSeconds

                if !isInstallMode {
                    switch sec {
                    case 2:
                        self.addSystemLog("UEFI 引导完成，正在启动 fnOS 系统内核与存储池服务...", tag: "BOOT", level: .info)
                    case 6:
                        self.addSystemLog("正在探测虚拟机局域网 IP 与飞牛 Web 控制台端口 (\(self.settings.webPort))...", tag: "NET", level: .info)
                    default:
                        if sec > 6 && sec % 8 == 0 {
                            self.addSystemLog("正在等待系统服务就绪 (已耗时 \(sec)s)...", tag: "BOOT", level: .info)
                        }
                    }
                }
            }
        }
    }

    private func stopBootProgressTimer() {
        bootProgressTimer?.invalidate()
        bootProgressTimer = nil
    }

    private func allocatedDiskMegabytes(at path: String) -> Int {
        var st = stat()
        if stat(path, &st) == 0 {
            let bytes = Int64(st.st_blocks) * 512
            return max(0, Int(bytes / (1024 * 1024)))
        }
        return 0
    }

    public var needsISODownloadToBoot: Bool {
        let diskURL = URL(fileURLWithPath: settings.vmDataDirectory).appendingPathComponent("fnos_system.raw")
        let actuallyInstalled = storageService.isDiskInstalled(url: diskURL)
        if !actuallyInstalled {
            ISOFetcherService.shared.refreshBuiltInISOState()
            return !ISOFetcherService.shared.hasBuiltInISO && !FileManager.default.fileExists(atPath: settings.isoPath)
        }
        return false
    }

    public func startVM(forceInstallMode: Bool = false) {
        guard status == .stopped || status == .error else { return }

        errorMessage = nil
        addSystemLog("收到启动指令，正在初始化虚拟化环境...", tag: "ENGINE", level: .info)

        Task { [weak self] in
            guard let self = self else { return }

            // 1. 存储健康与外置移动硬盘预检
            let health = self.storageService.checkStorageHealth(at: self.settings.dataStorageDirectory)
            if !health.isHealthy {
                let err = health.errorMessage ?? "数据存储目录不可用"
                self.status = .error
                self.errorMessage = err
                self.addSystemLog("存储健康预检未通过: \(err)", tag: "STORAGE", level: .error)
                return
            }

            do {
                let vmDir = try storageService.ensureDirectory(at: settings.vmDataDirectory)
                let diskURL = try storageService.ensureSparseDisk(
                    directory: vmDir,
                    sizeGB: settings.diskSizeGB
                )

                // 自动侦测磁盘是否已安装系统
                let actuallyInstalled = storageService.isDiskInstalled(url: diskURL)
                if !actuallyInstalled {
                    settings.isInstalled = false
                    settings.attachISO = true
                    settings.save()
                }

                // 自动绑定内置镜像路径
                ISOFetcherService.shared.refreshBuiltInISOState()
                if ISOFetcherService.shared.hasBuiltInISO {
                    settings.isoPath = ISOFetcherService.shared.builtInISOPath
                    settings.save()
                }

                let shouldAttachISO = forceInstallMode || (!actuallyInstalled) || (settings.attachISO && ISOFetcherService.shared.hasBuiltInISO)
                if shouldAttachISO {
                    guard FileManager.default.fileExists(atPath: settings.isoPath) else {
                        self.status = .stopped
                        let msg = "尚未内置系统镜像，请点击一键获取官方 ARM64 镜像"
                        self.errorMessage = msg
                        self.addSystemLog(msg, tag: "ERROR", level: .error)
                        return
                    }
                    self.addSystemLog("已挂载内置 ARM64 安装镜像 (fnos_arm64.iso)，进入全自动无人值守安装模式", tag: "ISO", level: .info)
                } else {
                    self.addSystemLog("检测到已安装的系统盘，进入常规快速启动模式", tag: "STORAGE", level: .info)
                }

                self.status = shouldAttachISO ? .installing : .starting
                self.startBootProgressTimer(isInstallMode: shouldAttachISO)

                let efiStore = try storageService.ensureEFIVariableStore(directory: vmDir, recreate: !actuallyInstalled)
                let machineID = storageService.ensureMachineIdentifier(directory: vmDir)
                let mac = storageService.ensureMACAddress(directory: vmDir)
                self.targetMAC = mac

                let config = VZVirtualMachineConfiguration()

                // 1. BootLoader
                if shouldAttachISO {
                    self.addSystemLog("正在提取 ARM64 安装内核与无人值守引导盘...", tag: "BOOT", level: .info)
                    let (kernelURL, initrdURL) = try storageService.prepareUnattendedInstallerAssets(
                        isoPath: settings.isoPath,
                        directory: vmDir
                    )
                    let linuxBootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
                    linuxBootLoader.initialRamdiskURL = initrdURL
                    linuxBootLoader.commandLine = "console=hvc0 quiet"
                    config.bootLoader = linuxBootLoader
                } else {
                    let bootloader = VZEFIBootLoader()
                    bootloader.variableStore = efiStore
                    config.bootLoader = bootloader
                }

                // 2. Platform
                let platform = VZGenericPlatformConfiguration()
                platform.machineIdentifier = machineID
                config.platform = platform

                // 3. CPU & Memory
                let minCPU = VZVirtualMachineConfiguration.minimumAllowedCPUCount
                let maxCPU = VZVirtualMachineConfiguration.maximumAllowedCPUCount
                let activeCPU = max(minCPU, min(settings.cpuCount, maxCPU))
                config.cpuCount = activeCPU

                let minMem = VZVirtualMachineConfiguration.minimumAllowedMemorySize
                let maxMem = VZVirtualMachineConfiguration.maximumAllowedMemorySize
                let requestedMem = UInt64(settings.memorySizeGB) * 1024 * 1024 * 1024
                config.memorySize = max(minMem, min(requestedMem, maxMem))
                self.addSystemLog("分配硬件资源: \(activeCPU) 核 CPU / \(settings.memorySizeGB) GB 内存 / VirtIO 气球回收已开启", tag: "HW", level: .info)

                // 4. Storage Devices (High Performance VirtIO Block with Caching & fsync)
                var storageDevices: [VZStorageDeviceConfiguration] = []

                // Primary Target Disk (Disk 0 -> /dev/vda, System OS)
                let targetAttachment = try VZDiskImageStorageDeviceAttachment(
                    url: diskURL,
                    readOnly: false,
                    cachingMode: .cached,
                    synchronizationMode: .fsync
                )
                let targetBlock = VZVirtioBlockDeviceConfiguration(attachment: targetAttachment)
                storageDevices.append(targetBlock)

                // Secondary Data Disk (Disk 1 -> /dev/vdb, for fnOS Storage Pool / 存储空间)
                let dataDirURL = try storageService.ensureDirectory(at: settings.dataStorageDirectory)
                let dataDiskURL = try storageService.ensureDataDisk(
                    directory: dataDirURL,
                    sizeGB: settings.dataDiskSizeGB
                )
                let dataAttachment = try VZDiskImageStorageDeviceAttachment(
                    url: dataDiskURL,
                    readOnly: false,
                    cachingMode: .cached,
                    synchronizationMode: .fsync
                )
                let dataBlock = VZVirtioBlockDeviceConfiguration(attachment: dataAttachment)
                storageDevices.append(dataBlock)
                self.addSystemLog("挂载数据存储盘: \(dataDiskURL.path) (\(settings.dataDiskSizeGB) GB · 动态按需占用)", tag: "STORAGE", level: .info)

                // Optional ISO Installer (Disk 2 -> /dev/vdc)
                if shouldAttachISO {
                    let isoURL = URL(fileURLWithPath: settings.isoPath)
                    let isoAttachment = try VZDiskImageStorageDeviceAttachment(
                        url: isoURL,
                        readOnly: true,
                        cachingMode: .cached,
                        synchronizationMode: .none
                    )
                    let isoBlock = VZVirtioBlockDeviceConfiguration(attachment: isoAttachment)
                    storageDevices.append(isoBlock)
                }
                config.storageDevices = storageDevices

                // 4.1 VirtIO Memory Balloon Device (动态内存伸缩与物理内存回垦)
                let balloonConfig = VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
                config.memoryBalloonDevices = [balloonConfig]

                // 4.2 VirtIO Hardware Entropy Device (Apple Silicon 硬件真随机数透传 -> /dev/urandom)
                let entropyConfig = VZVirtioEntropyDeviceConfiguration()
                config.entropyDevices = [entropyConfig]

                // 5. Shared Folders (VirtIO-FS) - 挂载数据存储目录或安全共享目录
                var fsDevices: [VZDirectorySharingDeviceConfiguration] = []
                let safeSharedPath = "\(settings.dataStorageDirectory)/Shared"
                try? FileManager.default.createDirectory(atPath: safeSharedPath, withIntermediateDirectories: true)
                let sharedDir = VZSharedDirectory(url: URL(fileURLWithPath: safeSharedPath), readOnly: false)
                let singleShare = VZSingleDirectoryShare(directory: sharedDir)
                let fsConfig = VZVirtioFileSystemDeviceConfiguration(tag: "fnos_shared")
                fsConfig.share = singleShare
                fsDevices.append(fsConfig)
                config.directorySharingDevices = fsDevices

                // 6. Network Device (NAT)
                let netAttachment = VZNATNetworkDeviceAttachment()
                let netConfig = VZVirtioNetworkDeviceConfiguration()
                netConfig.attachment = netAttachment
                netConfig.macAddress = mac
                config.networkDevices = [netConfig]
                self.addSystemLog("绑定 VirtIO 网络适配器 (MAC: \(mac.string))", tag: "NET", level: .info)

                // 7. Graphics & Input
                let graphics = VZVirtioGraphicsDeviceConfiguration()
                graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1440, heightInPixels: 900)]
                config.graphicsDevices = [graphics]
                config.keyboards = [VZUSBKeyboardConfiguration()]
                config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

                // 8. Serial Console Output (for boot log capture)
                let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
                let pipe = Pipe()
                serial.attachment = VZFileHandleSerialPortAttachment(
                    fileHandleForReading: nil,
                    fileHandleForWriting: pipe.fileHandleForWriting
                )
                config.serialPorts = [serial]
                self.consolePipe = pipe

                pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                        Task { @MainActor in
                            self?.appendSerialConsoleOutput(str)
                        }
                    }
                }

                // Validate
                try config.validate()

                // Create VM
                let vm = VZVirtualMachine(configuration: config)
                vm.delegate = self
                self.vzVirtualMachine = vm

                // Attach Dynamic Performance Engine (VirtIO Ballooning & Memory Pressure Adaptation)
                VMPerformanceEngine.shared.attach(
                    vm: vm,
                    configuredMemoryGB: settings.memorySizeGB,
                    enabled: settings.dynamicOptimization
                )

                // Start
                vm.start { [weak self] result in
                    Task { @MainActor in
                        guard let self = self else { return }
                        switch result {
                        case .success:
                            self.status = shouldAttachISO ? .installing : .starting
                            self.addSystemLog(
                                shouldAttachISO
                                    ? "Apple Virtualization 实例已启动，正在执行 ARM64 UEFI 安装引导..."
                                    : "Apple Virtualization 实例已启动，正在引导 fnOS 系统...",
                                tag: "BOOT",
                                level: .success
                            )
                            self.startNetworkMonitoring(targetMAC: mac)
                        case .failure(let err):
                            self.stopBootProgressTimer()
                            self.status = .error
                            let msg = "启动虚拟机失败: \(err.localizedDescription)"
                            self.errorMessage = msg
                            self.addSystemLog(msg, tag: "ERROR", level: .error)
                            VMPerformanceEngine.shared.detach()
                        }
                    }
                }
            } catch {
                self.stopBootProgressTimer()
                self.status = .error
                self.errorMessage = error.localizedDescription
                self.addSystemLog("虚拟化配置异常: \(error.localizedDescription)", tag: "ERROR", level: .error)
            }
        }
    }

    public func stopVM(force: Bool = false) {
        guard let vm = vzVirtualMachine, status.isRunningOrStarting else { return }
        status = .stopping
        stopBootProgressTimer()
        addSystemLog(force ? "正在强制关闭虚拟机实例..." : "正在向系统发送 ACPI 关机指令...", tag: "ENGINE", level: .warning)

        VMPerformanceEngine.shared.detach()
        networkMonitor.stopMonitoring()
        consolePipe?.fileHandleForReading.readabilityHandler = nil
        consolePipe = nil

        if force {
            vm.stop { [weak self] _ in
                Task { @MainActor in
                    self?.status = .stopped
                    self?.vzVirtualMachine = nil
                    self?.currentIP = nil
                    self?.isWebUIAvailable = false
                    self?.addSystemLog("虚拟机已停止运行", tag: "ENGINE", level: .info)
                }
            }
        } else {
            do {
                try vm.requestStop()
                // Set fallback timeout 15 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    if self?.status == .stopping {
                        self?.stopVM(force: true)
                    }
                }
            } catch {
                vm.stop { [weak self] _ in
                    Task { @MainActor in
                        self?.status = .stopped
                        self?.vzVirtualMachine = nil
                        self?.currentIP = nil
                        self?.isWebUIAvailable = false
                        self?.addSystemLog("虚拟机已停止运行", tag: "ENGINE", level: .info)
                    }
                }
            }
        }
    }

    public func pauseVM() {
        guard let vm = vzVirtualMachine, status == .running else { return }
        addSystemLog("正在挂起虚拟机并释放宿主 CPU 算力...", tag: "ENGINE", level: .info)
        if vm.canPause {
            vm.pause { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.status = .paused
                        self.addSystemLog("虚拟系统已进入挂起待机状态", tag: "ENGINE", level: .success)
                    case .failure(let err):
                        let msg = "暂停挂起失败: \(err.localizedDescription)"
                        self.errorMessage = msg
                        self.addSystemLog(msg, tag: "ERROR", level: .error)
                    }
                }
            }
        } else {
            self.status = .paused
            self.addSystemLog("虚拟系统已进入挂起待机状态", tag: "ENGINE", level: .success)
        }
    }

    public func resumeVM() {
        guard let vm = vzVirtualMachine, status == .paused else { return }
        addSystemLog("正在从挂起状态唤醒虚拟系统...", tag: "ENGINE", level: .info)
        if vm.canResume {
            vm.resume { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.status = .running
                        self.addSystemLog("虚拟系统已恢复全速运行", tag: "ENGINE", level: .success)
                    case .failure(let err):
                        let msg = "恢复运行失败: \(err.localizedDescription)"
                        self.errorMessage = msg
                        self.addSystemLog(msg, tag: "ERROR", level: .error)
                    }
                }
            }
        } else {
            self.status = .running
            self.addSystemLog("虚拟系统已恢复全速运行", tag: "ENGINE", level: .success)
        }
    }

    public func togglePlayPause() {
        switch status {
        case .running:
            pauseVM()
        case .paused:
            resumeVM()
        case .stopped, .error:
            startVM()
        default:
            break
        }
    }

    public func resetVM() {
        guard status.isRunningOrStarting else { return }
        addSystemLog("正在执行虚拟机強制重置并重新引导...", tag: "ENGINE", level: .warning)
        stopVM(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startVM(forceInstallMode: false)
        }
    }

    public func migrateAndApplyStorage(from oldDir: String, to newDir: String, sizeGB: Int) {
        let shouldRestartAfter = status.isRunningOrStarting || status == .paused
        if oldDir != newDir {
            addSystemLog("正在将数据存储从 \(oldDir) 迁移至 \(newDir) 并清理原目录文件...", tag: "STORAGE", level: .info)
        } else {
            addSystemLog("正在更新虚拟数据盘容量上限为 \(sizeGB) GB...", tag: "STORAGE", level: .info)
        }

        let performMigration: () -> Void = { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try StorageService.shared.migrateDataStorage(from: oldDir, to: newDir, sizeGB: sizeGB)
                    Task { @MainActor in
                        guard let self = self else { return }
                        if oldDir != newDir {
                            self.addSystemLog("数据已成功迁移至 \(newDir)，旧目录中的数据文件已删除", tag: "STORAGE", level: .success)
                        }
                        SystemMetricsService.shared.syncWith(status: self.status, settings: self.settings)
                        if shouldRestartAfter {
                            self.startVM(forceInstallMode: false)
                        }
                    }
                } catch {
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.addSystemLog("数据存储迁移失败: \(error.localizedDescription)", tag: "ERROR", level: .error)
                        if shouldRestartAfter {
                            self.startVM(forceInstallMode: false)
                        }
                    }
                }
            }
        }

        if shouldRestartAfter, let vm = vzVirtualMachine {
            status = .stopping
            stopBootProgressTimer()
            VMPerformanceEngine.shared.detach()
            networkMonitor.stopMonitoring()
            consolePipe?.fileHandleForReading.readabilityHandler = nil
            consolePipe = nil
            vm.stop { [weak self] _ in
                Task { @MainActor in
                    self?.status = .stopped
                    self?.vzVirtualMachine = nil
                    self?.currentIP = nil
                    self?.isWebUIAvailable = false
                    performMigration()
                }
            }
        } else {
            performMigration()
        }
    }

    public var formattedAccessAddress: String {
        if settings.isCustomDomainEnabled {
            let domain = "\(settings.customDomainPrefix).fnos"
            if let ip = currentIP, !ip.isEmpty {
                return "\(domain) · \(ip)"
            }
            return "\(domain) · 192.168.64.2"
        } else {
            if let ip = currentIP, !ip.isEmpty {
                return "\(ip):\(settings.webPort)"
            }
            return "192.168.64.2:\(settings.webPort)"
        }
    }

    public var webConsoleURL: URL? {
        if settings.isCustomDomainEnabled,
           let mapping = HostsManager.shared.getCurrentDomainMapping(),
           let ip = currentIP,
           mapping.ip == ip {
            return URL(string: "http://\(mapping.domain):\(settings.webPort)")
        }
        if let ip = currentIP, !ip.isEmpty {
            return URL(string: "http://\(ip):\(settings.webPort)")
        }
        return URL(string: "http://127.0.0.1:\(settings.webPort)")
    }

    public func markInstalledAndRestart() {
        addSystemLog("标记系统安装完成，正在弹出安装镜像并重启进入正常模式...", tag: "INSTALL", level: .success)
        settings.isInstalled = true
        settings.attachISO = false
        settings.save()

        stopVM(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startVM(forceInstallMode: false)
        }
    }

    private func startNetworkMonitoring(targetMAC: VZMACAddress) {
        networkMonitor.startMonitoring(targetMAC: targetMAC, targetPort: settings.webPort) { [weak self] ip in
            Task { @MainActor in
                guard let self = self else { return }
                let isNewIP = (self.currentIP != ip)
                self.currentIP = ip
                if isNewIP {
                    self.addSystemLog("侦测到虚拟机局域网地址: \(ip)，正在等待飞牛 Web 控制台端口 (\(self.settings.webPort)) 就绪...", tag: "NET", level: .info)
                }
            }
        } onPortOpen: { [weak self] isOpen in
            Task { @MainActor in
                guard let self = self else { return }
                let becameAvailable = (!self.isWebUIAvailable && isOpen)
                self.isWebUIAvailable = isOpen
                if isOpen && (self.status == .starting || self.status == .installing) {
                    self.stopBootProgressTimer()
                    self.status = .running
                    self.settings.isInstalled = true
                    self.settings.attachISO = false
                    self.settings.save()
                    self.addSystemLog("飞牛 Web 控制台已就绪，访问地址: http://\(self.settings.customDomainPrefix).fnos (或 http://\(self.currentIP ?? "192.168.64.2"):\(self.settings.webPort))", tag: "READY", level: .success)
                } else if becameAvailable {
                    self.addSystemLog("飞牛 Web 控制台服务 (端口 \(self.settings.webPort)) 已在线", tag: "READY", level: .success)
                }
            }
        }
    }

    private func appendSerialConsoleOutput(_ rawText: String) {
        let ansiPattern = #"\x1b\[[0-9;?=-]*[a-zA-Z]|\x1b\([0-9a-zA-Z]|\x1b[=>]|\[\?[0-9]+[hl]|\[[0-9;-]+[a-zA-Z]"#
        let cleaned = rawText
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        let lines = cleaned.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // 过滤终端字符画 Banner、物理硬件专属服务噪音及 fsck 进度条碎片
            if trimmed.contains("█") || trimmed.contains("╔") || trimmed.contains("╚") || trimmed.contains("═") {
                continue
            }
            if trimmed.contains("exFAT-fs") || trimmed.contains("F2FS-fs") || trimmed.contains("erofs") || trimmed.contains("failed to recognize") || trimmed.contains("superblock") {
                continue
            }
            if trimmed.contains("led-set.service") || trimmed.contains("set_gpio-init.service") || trimmed.contains("LED Setting Service") || trimmed.contains("GPIO Initialization Service") {
                continue
            }
            if trimmed.hasPrefix("/dev/vda2: |") || trimmed == "trim" {
                continue
            }

            if trimmed.contains("login:") {
                addSystemLog("虚拟终端已就绪 (trim login) — 首次使用无默认密码，请点击「控制台 ↗」或访问 http://nas.fnos 创建管理员账号", tag: "READY", level: .success)
                if self.status == .starting, self.currentIP != nil {
                    self.stopBootProgressTimer()
                    self.status = .running
                }
                continue
            }

            if trimmed.hasPrefix("[FNOS_AUTO_INSTALL_DONE]") {
                let msg = trimmed.replacingOccurrences(of: "[FNOS_AUTO_INSTALL_DONE]", with: "").trimmingCharacters(in: .whitespaces)
                addSystemLog(msg.isEmpty ? "飞牛 fnOS 系统全自动安装完成，正在重启进入正式系统..." : msg, tag: "READY", level: .success)
                continue
            }

            let knownPrefixes: [(prefix: String, tag: String, level: VMLogEntry.Level)] = [
                ("[BOOT]", "BOOT", .info),
                ("[ISO]", "ISO", .info),
                ("[STORAGE]", "STORAGE", .info),
                ("[INSTALL]", "INSTALL", .info),
                ("[UEFI]", "UEFI", .info),
                ("[READY]", "READY", .success),
                ("[ERROR]", "ERROR", .error)
            ]

            var matched = false
            for item in knownPrefixes {
                if trimmed.hasPrefix(item.prefix) {
                    let msg = String(trimmed.dropFirst(item.prefix.count)).trimmingCharacters(in: .whitespaces)
                    if !msg.isEmpty {
                        addSystemLog(msg, tag: item.tag, level: item.level)
                    }
                    matched = true
                    break
                }
            }

            if !matched {
                addSystemLog(trimmed, tag: "TTY", level: .info)
            }
        }
    }
}

extension VMManager: VZVirtualMachineDelegate {
    nonisolated public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let wasInstalling = (self.status == .installing)
            let wasBooting = self.status == .starting || self.status == .installing
            self.stopBootProgressTimer()
            self.networkMonitor.stopMonitoring()
            self.consolePipe?.fileHandleForReading.readabilityHandler = nil
            self.consolePipe = nil
            self.vzVirtualMachine = nil

            if wasInstalling {
                let diskURL = URL(fileURLWithPath: self.settings.vmDataDirectory).appendingPathComponent("fnos_system.raw")
                if self.storageService.isDiskInstalled(url: diskURL) {
                    self.settings.isInstalled = true
                    self.settings.attachISO = false
                    self.settings.save()
                    self.status = .stopped
                    self.addSystemLog("无人值守安装阶段已完成，正在从虚拟系统盘启动飞牛 fnOS...", tag: "READY", level: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.startVM(forceInstallMode: false)
                    }
                    return
                }
            }

            self.status = .stopped
            self.currentIP = nil
            self.isWebUIAvailable = false
            self.addSystemLog("客户机操作系统已关机停止", tag: "ENGINE", level: .warning)
            if wasBooting && self.errorMessage == nil {
                self.errorMessage = "虚拟机系统引导停止。如果使用的是首次安装镜像，请确认镜像支持 ARM64 UEFI。"
            }
        }
    }

    nonisolated public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        Task { @MainActor in
            self.stopBootProgressTimer()
            self.status = .error
            let msg = "虚拟机异常退出: \(error.localizedDescription)"
            self.errorMessage = msg
            self.addSystemLog(msg, tag: "ERROR", level: .error)
            self.networkMonitor.stopMonitoring()
            self.currentIP = nil
            self.isWebUIAvailable = false
        }
    }
}
