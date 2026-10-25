import SwiftUI
import AppKit

public struct MainWindowView: View {
    @StateObject var vmManager = VMManager()
    @StateObject var isoFetcher = ISOFetcherService.shared
    @State private var selectedTab: TabItem = CommandLine.arguments.contains("--tab-settings") ? .settings : .storage
    @State private var hoveredFolderId: UUID? = nil

    private var l10n: LocalizedStrings {
        vmManager.settings.language.strings
    }

    enum TabItem: String, CaseIterable, Identifiable {
        case web = "web"
        case storage = "storage"
        case display = "display"
        case settings = "settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .web: return "globe"
            case .storage: return "cylinder.split.1x2"
            case .display: return "display"
            case .settings: return "gearshape"
            }
        }

        func title(for l10n: LocalizedStrings) -> String {
            switch self {
            case .web: return l10n.tabWeb
            case .storage: return l10n.tabStorage
            case .display: return l10n.tabDisplay
            case .settings: return l10n.tabSettings
            }
        }
    }

    public var body: some View {
        ZStack {
            // 1. macOS 原生毛玻璃背景 (Frosted Glass Vibrancy)
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // 2. 深色高级质感半透遮罩 (Dark Frosted Tint Overlay)
            Color(red: 0.10, green: 0.11, blue: 0.14, opacity: 0.88)
                .ignoresSafeArea()

            // 3. 核心界面内容
            VStack(spacing: 0) {
                // 顶部单行一体化导航栏 (Unified Top Bar with Inline Traffic Lights Space)
                topHeaderBar

                Divider()
                    .background(Color.white.opacity(0.07))

                // 内容切换主视窗 (Top Aligned to match mockup spacing)
                ZStack(alignment: .top) {
                    switch selectedTab {
                    case .storage:
                        storagePoolsView
                    case .web:
                        webConsoleView
                    case .display:
                        vmDisplayView
                    case .settings:
                        settingsView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 940, minHeight: 535)
        .background(WindowConfigurator())
        .preferredColorScheme(.dark)
        .alert(isPresented: Binding(
            get: { vmManager.errorMessage != nil },
            set: { if !$0 { vmManager.errorMessage = nil } }
        )) {
            Alert(
                title: Text(l10n.systemNotice),
                message: Text(vmManager.errorMessage ?? "未知错误"),
                dismissButton: .default(Text(l10n.confirm))
            )
        }
        .onChange(of: vmManager.status) { _, newStatus in
            if newStatus == .installing {
                selectedTab = .display
            } else if newStatus == .running && selectedTab == .display {
                selectedTab = .web
            }
        }
        .frame(minWidth: 960, idealWidth: 960, minHeight: 650, idealHeight: 670)
    }

    // MARK: - 顶部单行一体化工具栏 (Matching Design Mockup 1:1)
    private var topHeaderBar: some View {
        HStack(spacing: 16) {
            // 左侧品牌与状态（左留 78pt 完美避开窗口红黄绿三色按钮）
            HStack(spacing: 12) {
                ServerChassisAppleIcon()

                Text(l10n.appTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                // 实时在线/离线呼吸指示器（设计稿直接悬浮展示，无生硬外框）
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.85), radius: 5, x: 0, y: 0)

                    Text(statusText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .padding(.leading, 6)
            }

            Spacer()

            // 中央 4 项胶囊分段导航 (Center Capsule Navigation)
            HStack(spacing: 2) {
                ForEach(TabItem.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                            Text(tab.title(for: l10n))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .foregroundColor(selectedTab == tab ? .white : Color.white.opacity(0.55))
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.white.opacity(0.18) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.35))
            .cornerRadius(11)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.08), lineWidth: 1))

            Spacer()

            // 右侧主控制区 (Run / Stop Capsule Button)
            HStack(spacing: 10) {
                if let ip = vmManager.currentIP,
                   let url = URL(string: "http://\(ip):\(vmManager.settings.webPort)") {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Image(systemName: "safari")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(7)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(l10n.openSafariHelp)
                }

                if vmManager.status.isRunningOrStarting {
                    Button(action: { vmManager.stopVM() }) {
                        HStack(spacing: 6) {
                            Text(l10n.stopButton)
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    colors: [Color.red.opacity(0.95), Color(red: 0.8, green: 0.15, blue: 0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .shadow(color: Color.red.opacity(0.4), radius: 6, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        if vmManager.needsISODownloadToBoot {
                            selectISOFile()
                        } else {
                            vmManager.startVM()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(l10n.runButton)
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.12, green: 0.52, blue: 0.98), Color(red: 0.05, green: 0.44, blue: 0.92)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .shadow(color: Color.blue.opacity(0.45), radius: 6, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 78) // 预留窗口左上角交通灯空间
        .padding(.trailing, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Tab: Storage Pools (完全对应设计稿核心视窗)
    private var storagePoolsView: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左列: 双磁盘卡片 (System Boot Disk + Data Pool Disk)
            VStack(spacing: 16) {
                // 卡片 1: System Boot Disk (NVMe SSD - 64 GB)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        // 拟物化金属 Apple 硬盘图标
                        MetallicAppleDriveIcon()

                        VStack(alignment: .leading, spacing: 6) {
                            Text(l10n.systemBootDisk)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            Text(l10n.systemDiskSubtitle)
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.5))

                            // 渐变进度条
                            let systemPath = vmManager.settings.vmDataDirectory + "/fnos_system.raw"
                            let (usedBytes, usedStr) = StorageService.shared.getAllocatedFileSize(at: systemPath)
                            let totalBytes = Int64(64) * 1024 * 1024 * 1024
                            let progress = min(1.0, max(0.28, Double(usedBytes) / Double(totalBytes)))

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(Color.white.opacity(0.12))
                                        .frame(height: 7)
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.25, green: 0.70, blue: 0.98), Color(red: 0.10, green: 0.50, blue: 0.95)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .frame(width: geo.size.width * CGFloat(progress), height: 7)
                                }
                            }
                            .frame(height: 7)
                            .padding(.top, 2)

                            HStack {
                                Text(usedBytes > 0 ? "\(usedStr) \(l10n.usedWord) / 45.5 GB \(l10n.freeWord)" : "18.5 GB \(l10n.usedWord) / 45.5 GB \(l10n.freeWord)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.7))
                                    .lineLimit(1)
                                Spacer()
                                Text(l10n.apfsSparseBadge)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(20)
                .background(frostedCardBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))

                // 卡片 2: Data Pool Disk (fnOS Data Pool - 256 GB)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        // 科技感环形发光仪表盘 (Donut Ring Gauge)
                        DonutRingGauge(progress: 0.44)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(l10n.dataPoolDisk)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            Text(String(format: l10n.dataDiskSubtitle, vmManager.settings.dataDiskSizeGB))
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.5))

                            // 渐变进度条 (Cyan to Purple)
                            let dataPath = vmManager.settings.vmDataDirectory + "/fnos_data.raw"
                            let (dataUsed, dataStr) = StorageService.shared.getAllocatedFileSize(at: dataPath)
                            let dataProgress = dataUsed > 0 ? min(1.0, max(0.04, Double(dataUsed) / (Double(vmManager.settings.dataDiskSizeGB) * 1024 * 1024 * 1024))) : 0.44

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(Color.white.opacity(0.12))
                                        .frame(height: 7)
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.2, green: 0.75, blue: 0.95), Color(red: 0.55, green: 0.45, blue: 0.95)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .frame(width: geo.size.width * CGFloat(dataProgress), height: 7)
                                }
                            }
                            .frame(height: 7)
                            .padding(.top, 2)

                            HStack {
                                Text(dataUsed > 0 ? "\(dataStr) \(l10n.usedWord) / 256 GB \(l10n.freeWord)" : "112.4 GB \(l10n.usedWord) / 143.6 GB \(l10n.freeWord)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.7))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(l10n.raidStatus)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 0.3, green: 0.82, blue: 1.0))
                                    .lineLimit(1)
                            }
                        }
                    }

                    // 贴心指导文案（与整体色调融合）
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.3, green: 0.82, blue: 1.0))
                        Text(l10n.dataDiskHint)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
                .background(frostedCardBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .frame(maxWidth: .infinity)

            // 右列: VirtIO-FS Shared Folders 卡片
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.virtioSharedFolders)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Text(l10n.mappedMacFolders)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    Spacer()
                    Button(action: selectFolderFromMac) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text(l10n.addButton)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }

                // 文件夹列表项 (Matching Mockup with Native macOS Folder Icons & Counters)
                VStack(spacing: 0) {
                    ForEach(vmManager.settings.sharedFolders) { folder in
                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.hostPath)
                        }) {
                            HStack(spacing: 14) {
                                // 原生 Aqua 质感文件夹图标
                                MacFolderIcon(glyph: folder.iconGlyph)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.localizedName(for: vmManager.settings.language))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Text(folder.hostPath)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color.white.opacity(0.4))
                                        .lineLimit(1)
                                }

                                Spacer()

                                // 数量指示胶囊 (1, 3, 0, 1...)
                                Text("\(folderItemCount(for: folder.hostPath))")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.65))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(6)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.3))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 15)
                            .background(hoveredFolderId == folder.id ? Color.white.opacity(0.05) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovered in
                            hoveredFolderId = isHovered ? folder.id : nil
                        }
                        .contextMenu {
                            Button(l10n.revealInFinder) {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.hostPath)
                            }
                            Button(l10n.removeShare) {
                                vmManager.settings.sharedFolders.removeAll { $0.id == folder.id }
                                vmManager.settings.save()
                            }
                        }

                        if folder.id != vmManager.settings.sharedFolders.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                        }
                    }
                }
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
            .padding(20)
            .background(frostedCardBackground)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .frame(maxWidth: .infinity)
        }
        .padding(22)
    }

    // MARK: - Tab: Web Console (内嵌浏览器)
    private var webConsoleView: some View {
        Group {
            if vmManager.status == .running {
                WebDashboardView(vmManager: vmManager)
            } else {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "globe")
                            .font(.system(size: 38))
                            .foregroundColor(.blue)
                    }

                    VStack(spacing: 6) {
                        Text(vmManager.status == .starting ? l10n.webStarting : l10n.webNotRunning)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text(vmManager.status == .starting
                             ? l10n.webDetectingNet
                             : l10n.webStartGuide)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.55))
                    }

                    if vmManager.status != .starting {
                        Button(action: { vmManager.startVM() }) {
                            Text(l10n.startSystemBtn)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(
                                            colors: [Color.blue, Color(red: 0.1, green: 0.5, blue: 0.95)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Tab: VM Display
    private var vmDisplayView: some View {
        VStack(spacing: 0) {
            VMConsoleContainerView(vmManager: vmManager)
        }
    }

    // MARK: - Tab: Settings
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. 官方 ARM64 智能镜像卡片 (二合一)
                UnifiedISOCardView(
                    isoFetcher: isoFetcher,
                    vmManager: vmManager,
                    l10n: l10n,
                    onSelectCustomISO: { selectISOFile() }
                )

                // 2. 硬件规格与性能三档预设
                HardwarePresetCardView(
                    vmManager: vmManager,
                    l10n: l10n
                )

                // 3. 通用偏好设置 (界面语言)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l10n.languageSection)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text(l10n.languageSubtitle)
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.5))
                        }

                        Spacer()

                        // 3 语言切换胶囊 (中英繁)
                        HStack(spacing: 2) {
                            ForEach(AppLanguage.allCases) { lang in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        vmManager.settings.language = lang
                                        vmManager.settings.save()
                                    }
                                }) {
                                    Text(lang.displayName)
                                        .font(.system(size: 11, weight: vmManager.settings.language == lang ? .semibold : .regular))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .foregroundColor(vmManager.settings.language == lang ? .white : Color.white.opacity(0.6))
                                        .background(
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(vmManager.settings.language == lang ? Color.blue.opacity(0.9) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(9)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                }
                .padding(18)
                .background(frostedCardBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))

                // 4. 开源项目与开发者主页 (GitHub)
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 38, height: 38)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.developerSection)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("https://github.com/Xiaohantx/FnOS-Manager")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.blue.opacity(0.85))
                    }

                    Spacer()

                    Button(action: {
                        if let url = URL(string: "https://github.com/Xiaohantx/FnOS-Manager") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                            Text(l10n.visitGithubBtn)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(
                                    colors: [Color.blue.opacity(0.85), Color(red: 0.1, green: 0.45, blue: 0.9)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(frostedCardBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))

                // 5. 底部即时生效与版本状态提示
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 11))
                        Text(l10n.autoSaveHint)
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    Spacer()
                    Text("FnOS Manager v1.2 · Developed by Xiaohantx")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .padding(22)
        }
    }

    // MARK: - 辅助组件与计算属性
    private var frostedCardBackground: some View {
        Color.white.opacity(0.04)
    }

    private var statusColor: Color {
        switch vmManager.status {
        case .stopped: return .gray
        case .starting, .installing, .stopping: return .orange
        case .running: return .green
        case .paused: return .yellow
        case .error: return .red
        }
    }

    private var statusText: String {
        switch vmManager.status {
        case .running:
            return vmManager.currentIP != nil ? "\(l10n.onlinePrefix): \(vmManager.currentIP!)" : l10n.onlinePrefix
        case .paused:
            return "已挂起暂停"
        case .installing:
            return l10n.installing
        case .starting:
            return l10n.booting
        case .stopping:
            return l10n.stopping
        case .stopped:
            return l10n.offline
        case .error:
            return l10n.error
        }
    }

    private func folderItemCount(for path: String) -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return 0 }
        let visible = items.filter { !$0.hasPrefix(".") }
        return visible.count
    }

    private func selectISOFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = l10n.selectISOPrompt

        if panel.runModal() == .OK, let url = panel.url {
            let arch = StorageService.shared.detectISOArchitecture(path: url.path)
            if arch == .x86_64 {
                vmManager.errorMessage = "\(l10n.archIncompatibleTitle)：\n\(l10n.archIncompatibleMessage)"
                return
            }
            vmManager.settings.isoPath = url.path
            vmManager.settings.save()
            vmManager.startVM()
        }
    }

    private func selectFolderFromMac() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = l10n.selectFolderPrompt

        if panel.runModal() == .OK, let url = panel.url {
            let folderName = url.lastPathComponent
            var cleanTag = folderName.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            if cleanTag.isEmpty { cleanTag = "mac_share" }

            var finalTag = cleanTag
            var counter = 1
            while vmManager.settings.sharedFolders.contains(where: { $0.tag == finalTag }) {
                finalTag = "\(cleanTag)_\(counter)"
                counter += 1
            }

            let newFolder = SharedFolder(
                tag: finalTag,
                hostPath: url.path,
                readOnly: false,
                isEnabled: true
            )
            vmManager.settings.sharedFolders.append(newFolder)
            vmManager.settings.save()
        }
    }
}

// MARK: - 视觉组件: 拟物化金属 Apple 硬盘 (Metallic Apple Drive Icon)
struct MetallicAppleDriveIcon: View {
    var body: some View {
        ZStack {
            // 铝合金拉丝主体机壳
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.90, blue: 0.93),
                            Color(red: 0.72, green: 0.75, blue: 0.80),
                            Color(red: 0.58, green: 0.61, blue: 0.67)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 54, height: 66)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.8), Color.black.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 0, y: 3)

            // 顶部盘片金属盖板与 Apple 标志
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.80, green: 0.83, blue: 0.87),
                                    Color(red: 0.64, green: 0.67, blue: 0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 46, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                        )

                    // 盘心微凹圆盘与 Apple 标志
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.90, green: 0.92, blue: 0.95),
                                        Color(red: 0.70, green: 0.73, blue: 0.78)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)

                        Image(systemName: "apple.logo")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.39, blue: 0.44))
                            .shadow(color: Color.white.opacity(0.7), radius: 0.5, x: 0, y: 0.5)
                    }

                    // 四角微型防震螺丝孔
                    VStack {
                        HStack {
                            Circle().fill(Color.black.opacity(0.4)).frame(width: 2.2, height: 2.2)
                            Spacer()
                            Circle().fill(Color.black.opacity(0.4)).frame(width: 2.2, height: 2.2)
                        }
                        Spacer()
                        HStack {
                            Circle().fill(Color.black.opacity(0.4)).frame(width: 2.2, height: 2.2)
                            Spacer()
                            Circle().fill(Color.black.opacity(0.4)).frame(width: 2.2, height: 2.2)
                        }
                    }
                    .frame(width: 40, height: 34)
                }
                .padding(.top, 4)

                Spacer()

                // 底部排线金手指与状态灯细节
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 12, height: 2.5)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 7, height: 2.5)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .frame(width: 54, height: 66)

            // 右下角发光徽章 (Orange & Cyan Glow Badge)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.58, blue: 0.2), Color(red: 0.1, green: 0.65, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 19, height: 19)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.2))
                    .shadow(color: Color.orange.opacity(0.6), radius: 4, x: 0, y: 1)

                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(x: 18, y: 22)
        }
        .frame(width: 60, height: 70)
    }
}

// MARK: - 视觉组件: 环形科技发光仪表盘 (Donut Ring Gauge)
struct DonutRingGauge: View {
    var progress: Double = 0.44

    var body: some View {
        ZStack {
            // 背景暗色轨道
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)
                .frame(width: 68, height: 68)

            // 渐变高光环形弧线
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.88, blue: 0.95), // Cyan
                            Color(red: 0.25, green: 0.58, blue: 0.98), // Dodger Blue
                            Color(red: 0.45, green: 0.35, blue: 0.95)  // Purple
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(red: 0.10, green: 0.85, blue: 0.95).opacity(0.55), radius: 8, x: 0, y: 0)

            // 内核深色圆球
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.white.opacity(0.04), lineWidth: 1))
        }
        .frame(width: 74, height: 74)
    }
}

// MARK: - 视觉组件: 原生 Aqua 质感文件夹 (Mac Folder Icon)
struct MacFolderIcon: View {
    let glyph: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.68, blue: 1.0),
                            Color(red: 0.10, green: 0.50, blue: 0.96)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 32, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.6)
                )
                .shadow(color: Color.blue.opacity(0.35), radius: 3, x: 0, y: 1.5)

            Image(systemName: glyph)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
        }
        .frame(width: 34, height: 30)
    }
}

// MARK: - 视觉组件: 金属服务器机箱 Apple 图标
struct ServerChassisAppleIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.38, green: 0.42, blue: 0.46),
                            Color(red: 0.22, green: 0.25, blue: 0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1.5)

            VStack(spacing: 2.5) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 2) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 2.2, height: 2.2)
                        RoundedRectangle(cornerRadius: 0.8)
                            .fill(Color.white.opacity(0.35))
                            .frame(height: 1.8)
                    }
                }
            }
            .padding(.horizontal, 4)

            Image(systemName: "apple.logo")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 1)
                .offset(x: 3, y: 1.5)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - 原生毛玻璃背景封装 (NSVisualEffectView Wrapper)
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - 窗口样式配置器 (Window Configurator for Frameless Titlebar)
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.title = "FnOS Manager"
            window.setContentSize(NSSize(width: 940, height: 535))
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
