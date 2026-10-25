import SwiftUI
import AppKit
import ObjectiveC

// MARK: - 全局主菜单与窗口打开协调器
@MainActor
public final class AppWindowManager: NSObject {
    public static let shared = AppWindowManager()

    public var openAboutAction: (() -> Void)?
    public var openSettingsAction: (() -> Void)?
    public var openLogsAction: (() -> Void)?

    private override init() {
        super.init()
    }

    public func setupMenuAndObservers(
        openAbout: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openLogs: (() -> Void)? = nil
    ) {
        self.openAboutAction = openAbout
        self.openSettingsAction = openSettings
        if let openLogs = openLogs {
            self.openLogsAction = openLogs
        }
        configureMainMenu()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureMainMenu()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureMainMenu()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.fnnas.fnos.showAbout"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showAboutWindow()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.fnnas.fnos.showSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showSettingsWindow()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.fnnas.fnos.showLogs"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showLogsWindow()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.fnnas.fnos.startVM"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                VMManager.shared.startVM()
            }
        }
    }

    /// 精确构建左上角第一个应用菜单：1. 关于 FnOS Manager  2. 设置…  3. 查看运行日志…
    public func configureMainMenu() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        let appMenuItem: NSMenuItem
        if let first = mainMenu.items.first {
            appMenuItem = first
        } else {
            appMenuItem = NSMenuItem()
            mainMenu.addItem(appMenuItem)
        }

        // 移除多余的 File / Edit / View 等默认英文菜单，保持顶栏纯粹干净
        while mainMenu.items.count > 1 {
            mainMenu.removeItem(at: 1)
        }

        let appMenu = NSMenu(title: "FnOS Manager")

        // 1. 第一个：关于 FnOS Manager
        let aboutItem = NSMenuItem(
            title: "关于 FnOS Manager",
            action: #selector(handleOpenAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        // 2. 第二个：设置… (替换原有的 Services，快捷键 ⌘,)
        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(handleOpenSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        // 3. 第三个：查看运行日志… (快捷键 ⌘L)
        let logsItem = NSMenuItem(
            title: "查看运行日志…",
            action: #selector(handleOpenLogs(_:)),
            keyEquivalent: "l"
        )
        logsItem.target = self
        appMenu.addItem(logsItem)

        appMenu.addItem(NSMenuItem.separator())

        // 4. 标准窗口隐藏与退出控制
        let hideItem = NSMenuItem(
            title: "隐藏 FnOS Manager",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: "全部显示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 FnOS Manager",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        if NSApp.mainMenu !== mainMenu {
            NSApp.mainMenu = mainMenu
        }
    }

    @objc private func handleOpenAbout(_ sender: Any?) {
        showAboutWindow()
    }

    @objc private func handleOpenSettings(_ sender: Any?) {
        showSettingsWindow()
    }

    @objc private func handleOpenLogs(_ sender: Any?) {
        showLogsWindow()
    }

    public func showAboutWindow() {
        openAboutAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showSettingsWindow() {
        openSettingsAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showLogsWindow() {
        openLogsAction?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 「关于 FnOS Manager」独立窗口视图 (写清楚产品定位、核心架构与版权信息)
public struct AboutFnOSWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var updateChecker = UpdateChecker.shared

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            // 1. 原生毛玻璃与深色底色
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color(red: 0.08, green: 0.09, blue: 0.13, opacity: 0.94)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶栏 (居中标题，与主页面标题高度位置一致)
                ZStack {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.blue)

                        Text("关于 FnOS Manager")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 38)
                .padding(.top, 8)
                .padding(.horizontal, 14)

                // 头部品牌与版本标识
                VStack(spacing: 7) {
                    LogoBadgeView(size: 54)
                        .padding(.top, 2)
                        .shadow(color: Color.blue.opacity(0.22), radius: 10, x: 0, y: 3)

                    Text("FnOS Manager")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("飞牛私有云桌面管理器")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.62))

                    // 版本与更新状态组合胶囊 (极简克制，开阔无挤压)
                    HStack(spacing: 8) {
                        Text("v\(UpdateChecker.currentVersion) · ARM64")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 0.38, green: 0.78, blue: 1.0))
                            .padding(.horizontal, 8.5)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.05, green: 0.5, blue: 1.0).opacity(0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.blue.opacity(0.24), lineWidth: 0.8)
                            )

                        Button(action: {
                            if updateChecker.updateInfo?.hasUpdate == true {
                                Task {
                                    await updateChecker.downloadAndInstallUpdate()
                                }
                            } else {
                                Task {
                                    await updateChecker.checkForUpdates(manual: true)
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                if updateChecker.isChecking {
                                    ProgressView()
                                        .scaleEffect(0.45)
                                        .frame(width: 9, height: 9)
                                    Text("检查中...")
                                        .font(.system(size: 9.5, weight: .medium))
                                } else if updateChecker.isDownloading {
                                    ProgressView()
                                        .scaleEffect(0.45)
                                        .frame(width: 9, height: 9)
                                    Text("正在下载更新...")
                                        .font(.system(size: 9.5, weight: .medium))
                                } else if updateChecker.isInstalling {
                                    ProgressView()
                                        .scaleEffect(0.45)
                                        .frame(width: 9, height: 9)
                                    Text("正在安装并重启...")
                                        .font(.system(size: 9.5, weight: .medium))
                                } else if updateChecker.updateInfo?.hasUpdate == true {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8.5))
                                    Text("新版本 v\(updateChecker.updateInfo?.latestVersion ?? "")")
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 7.5, weight: .bold))
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 8.5))
                                        .foregroundColor(Color.green)
                                    Text(updateChecker.checkMessage == "已是最新版本" ? "已是最新" : (updateChecker.checkMessage ?? "已是最新"))
                                        .font(.system(size: 9.5, weight: .medium))
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 7.5))
                                        .opacity(0.4)
                                }
                            }
                            .foregroundColor(updateChecker.updateInfo?.hasUpdate == true ? .white : Color.white.opacity(0.78))
                            .padding(.horizontal, 8.5)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(updateChecker.updateInfo?.hasUpdate == true ?
                                          Color.green.opacity(0.85) :
                                          Color.white.opacity(0.06))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(updateChecker.updateInfo?.hasUpdate == true ?
                                            Color.green.opacity(0.9) :
                                            Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)

                // 系统与运行规格卡片 (精致、紧凑、毛玻璃)
                VStack(spacing: 0) {
                    aboutSpecRow(icon: "cpu", title: "虚拟化引擎", value: "Apple Virtualization (原生)")
                    Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 10)
                    aboutSpecRow(icon: "memorychip", title: "动态内存调度", value: "VirtIO 动态气球回垦")
                    Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 10)
                    aboutSpecRow(icon: "network", title: "控制台直达", value: "http://nas.fnos", isLink: true) {
                        if let url = URL(string: "http://nas.fnos") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 10)
                    aboutSpecRow(icon: "internaldrive", title: "数据存储模式", value: "APFS 稀疏动态扩容")
                }
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
                .padding(.horizontal, 18)

                Spacer(minLength: 8)

                // 官方链接与开源仓库入口
                HStack(spacing: 10) {
                    Link(destination: URL(string: "https://fnnas.com/")!) {
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                                .font(.system(size: 10.5))
                            Text("飞牛官方网站")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.35, green: 0.78, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.05, green: 0.5, blue: 1.0).opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.blue.opacity(0.22), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://github.com/Xiaohantx/FnOS-Manager")!) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text("项目仓库 (GitHub)")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

                // 底部版权声明
                Text("声明：底层系统与固件产权归属飞牛官方 (fnnas.com) 所有")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(.bottom, 9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(MiniWindowConfigurator(targetSize: NSSize(width: 380, height: 400), title: "关于 FnOS Manager"))
        .preferredColorScheme(.dark)
        .onAppear {
            if updateChecker.checkMessage == nil {
                Task {
                    await updateChecker.checkForUpdates()
                }
            }
        }
    }

    private func aboutSpecRow(icon: String, title: String, value: String, isLink: Bool = false, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 0.38, green: 0.78, blue: 1.0))
                .frame(width: 16)

            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            if isLink {
                Button(action: { action?() }) {
                    HStack(spacing: 3) {
                        Text(value)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7.5, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.35, green: 0.78, blue: 1.0))
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - 「偏好设置」独立窗口视图 (菜单栏设置项与主界面齿轮图标共用同一独立窗口)
public struct MiniSettingsSheetView: View {
    @ObservedObject var vmManager: VMManager
    @ObservedObject var isoFetcher = ISOFetcherService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isoPath: String = ""
    @State private var attachISO: Bool = true
    @State private var isoCheckStatus: String? = nil
    @State private var isoErrorText: String? = nil

    @State private var domainPrefix: String = "nas"
    @State private var isDomainEnabled: Bool = true
    @State private var autoStart: Bool = false
    @State private var dynamicBallooning: Bool = true
    @State private var lanAccessEnabled: Bool = true
    @State private var lanForwardedPortsText: String = "3000"
    @State private var dataStorageDirectory: String = ""
    @State private var dataDiskSizeGB: Int = 256

    public init(vmManager: VMManager) {
        self.vmManager = vmManager
        _isoPath = State(initialValue: vmManager.settings.isoPath)
        _attachISO = State(initialValue: vmManager.settings.attachISO)
        _domainPrefix = State(initialValue: vmManager.settings.customDomainPrefix)
        _isDomainEnabled = State(initialValue: vmManager.settings.isCustomDomainEnabled)
        _autoStart = State(initialValue: vmManager.settings.autoStartOnLogin)
        _dynamicBallooning = State(initialValue: vmManager.settings.dynamicOptimization)
        _lanAccessEnabled = State(initialValue: vmManager.settings.lanAccessEnabled)
        _lanForwardedPortsText = State(initialValue: vmManager.settings.lanForwardedPorts.map(String.init).joined(separator: ", "))
        _dataStorageDirectory = State(initialValue: vmManager.settings.dataStorageDirectory)
        _dataDiskSizeGB = State(initialValue: vmManager.settings.dataDiskSizeGB)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // 原生毛玻璃与深色底色
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color(red: 0.08, green: 0.09, blue: 0.13, opacity: 0.94)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶栏 (居中标题，与主页面标题高度位置一致)
                ZStack {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.blue)

                        Text("偏好设置")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 38)
                .padding(.top, 10)
                .padding(.horizontal, 14)

                // 设置内容列表 (独立窗口空间充裕，一屏完整展示无截断)
                VStack(alignment: .leading, spacing: 11) {
                    // 1. 系统安装镜像 (ARM64 ISO)
                    isoManagementSection

                    // 2. 数据存储位置与容量 (支持外置硬盘文件夹)
                    storageManagementSection

                    // 3. 常规与性能调度
                    VStack(alignment: .leading, spacing: 6) {
                        Text("常规与性能调度")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.45))

                        settingRow(
                            title: "登录时自动在后台启动",
                            desc: "系统开机静默启动虚拟化服务",
                            isOn: $autoStart
                        )

                        settingRow(
                            title: "自适应动态气球回收",
                            desc: "空闲时释放内存交还 macOS 宿主",
                            isOn: $dynamicBallooning
                        )
                    }

                    // 3. 网络与本地域名
                    VStack(alignment: .leading, spacing: 6) {
                        Text("网络与本地域名")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.45))

                        settingRow(
                            title: "允许局域网设备访问",
                            desc: "转发控制台及下方应用端口；路由器 DNS 需指向这台 Mac",
                            isOn: $lanAccessEnabled
                        )

                        HStack(spacing: 8) {
                            Text("应用转发端口")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.8))

                            TextField("3000, 8080", text: $lanForwardedPortsText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                        }
                        Text("逗号分隔；默认转发 3000。访问应用时使用 Mac 局域网 IP 和对应端口。")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.white.opacity(0.45))

                        // 自定义域名卡片
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("自定义本地域名")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundColor(.white)

                                        Text("/etc/hosts")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.white.opacity(0.08))
                                            )
                                            .foregroundColor(Color.white.opacity(0.6))
                                    }

                                    Text("本机域名写入 /etc/hosts；其他设备需配置路由器 DNS")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(Color.white.opacity(0.5))
                                }

                                Spacer()

                                Toggle("", isOn: $isDomainEnabled)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .green))
                            }

                            if isDomainEnabled {
                                // 域名输入与目标 IP
                                HStack(spacing: 8) {
                                    HStack(spacing: 0) {
                                        TextField("nas", text: $domainPrefix)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white)
                                            .frame(width: 54)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.white.opacity(0.08))
                                            )

                                        Text(".fnos")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.blue)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .padding(.leading, 4)
                                    }

                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundColor(Color.white.opacity(0.4))

                                    Text(vmManager.currentIP ?? "192.168.64.2")
                                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.45))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.white.opacity(0.06))
                                        )

                                    Spacer()

                                    Text("http://\(domainPrefix.trimmingCharacters(in: .whitespaces).isEmpty ? "nas" : domainPrefix).fnos:\(vmManager.settings.webPort)")
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color.white.opacity(0.75))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                Spacer(minLength: 6)

                // 底部保存并完成
                HStack {
                    Button(action: {
                        AppWindowManager.shared.showAboutWindow()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                            Text("关于 FnOS Manager")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: saveAndDismiss) {
                        Text("完成")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6.5)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(MiniWindowConfigurator(targetSize: NSSize(width: 445, height: 595), title: "偏好设置"))
        .preferredColorScheme(.dark)
        .onAppear {
            isoFetcher.refreshBuiltInISOState()
            if isoFetcher.hasBuiltInISO {
                isoFetcher.fetchLatestISO()
            }
        }
    }

    // MARK: - 系统安装镜像 (ARM64 ISO) 内置检测与一键获取/更新/清理
    private var isoManagementSection: some View {
        let currentISOInfo = isoFetcher.fetchedISO ?? ISOFetcherService.fallbackARMISO
        let activeMD5 = (isoFetcher.hasUpdateAvailable ? currentISOInfo.md5 : (isoFetcher.localISOMD5 ?? currentISOInfo.md5)).lowercased()
        let shortMD5 = activeMD5.count > 16 ? "\(activeMD5.prefix(8))…\(activeMD5.suffix(6))" : activeMD5

        return VStack(alignment: .leading, spacing: 6) {
            Text("系统安装镜像 (ARM64 ISO)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.45))

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 6) {
                            Text("官方 ARM64 镜像")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            // 状态胶囊
                            HStack(spacing: 3.5) {
                                Circle()
                                    .fill(isoStatusBadgeColor)
                                    .frame(width: 5, height: 5)
                                Text(isoStatusBadgeText)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(isoStatusBadgeColor)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isoStatusBadgeColor.opacity(0.12))
                            .cornerRadius(5)
                        }

                        // 副标题：显示固定字数下载进度、错误提示、或者单行 MD5 校验值
                        if isoFetcher.isDownloading {
                            Text("\(isoFetcher.downloadedSizeStr) / \(isoFetcher.totalSizeStr) · \(isoFetcher.downloadSpeedStr)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(Color(red: 0.35, green: 0.82, blue: 1.0))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .transaction { $0.animation = nil }
                        } else if let err = isoFetcher.errorMessage {
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        } else if isoFetcher.hasBuiltInISO {
                            if isoFetcher.hasUpdateAvailable {
                                Text("发现新版本 · MD5: \(shortMD5)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            } else {
                                Text("MD5: \(shortMD5)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.5))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        } else {
                            Text("内置管理 · 自动签名下载并挂载引导")
                                .font(.system(size: 10.5))
                                .foregroundColor(Color.white.opacity(0.48))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    Spacer(minLength: 8)

                    // 右侧操作区：根据是否正在下载 / 是否包含内置镜像自动切换
                    if isoFetcher.isDownloading {
                        HStack(spacing: 6) {
                            Text(String(format: "%3d%%", Int(isoFetcher.downloadProgress * 100)))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(Color(red: 0.35, green: 0.82, blue: 1.0))
                                .frame(width: 34, alignment: .trailing)
                                .fixedSize(horizontal: true, vertical: false)
                                .transaction { $0.animation = nil }

                            Button(action: {
                                isoFetcher.cancelDownload()
                            }) {
                                Text("取消")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.8))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if isoFetcher.hasBuiltInISO {
                        // 已内置镜像：单行并排显示「检查更新（若 MD5 不同则显示更新镜像）」+「清理镜像」
                        HStack(spacing: 6) {
                            Button(action: {
                                if isoFetcher.hasUpdateAvailable {
                                    isoFetcher.downloadBuiltInISO { savedPath in
                                        vmManager.settings.isoPath = savedPath
                                        vmManager.settings.attachISO = true
                                        vmManager.settings.save()
                                        SystemMetricsService.shared.syncWith(status: vmManager.status, settings: vmManager.settings)
                                    }
                                } else {
                                    isoFetcher.checkRemoteUpdate()
                                }
                            }) {
                                HStack(spacing: 3.5) {
                                    ZStack {
                                        if isoFetcher.isFetching {
                                            ProgressView()
                                                .controlSize(.mini)
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: isoFetcher.hasUpdateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                    }
                                    .frame(width: 11, height: 11)

                                    Text(
                                        isoFetcher.isFetching
                                            ? "正在检查"
                                            : (isoFetcher.hasUpdateAvailable ? "更新镜像" : (isoFetcher.checkStatusMessage ?? "检查更新"))
                                    )
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .lineLimit(1)
                                }
                                .foregroundColor(.white)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 8.5)
                                .padding(.vertical, 5.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isoFetcher.hasUpdateAvailable ? Color.orange : Color.blue.opacity(0.85))
                                )
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                isoFetcher.clearBuiltInISO()
                                vmManager.settings.isoPath = ""
                                vmManager.settings.save()
                                SystemMetricsService.shared.syncWith(status: vmManager.status, settings: vmManager.settings)
                            }) {
                                HStack(spacing: 3.5) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9.5, weight: .medium))
                                    Text("清理镜像")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 8.5)
                                .padding(.vertical, 5.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.14))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    } else {
                        // 未内置镜像：仅显示「获取镜像」
                        Button(action: {
                            isoFetcher.downloadBuiltInISO { savedPath in
                                vmManager.settings.isoPath = savedPath
                                vmManager.settings.attachISO = true
                                vmManager.settings.save()
                                SystemMetricsService.shared.syncWith(status: vmManager.status, settings: vmManager.settings)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("获取镜像")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color(red: 0.1, green: 0.45, blue: 0.92)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 下载中进度条
                if isoFetcher.isDownloading {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 4)
                            Capsule()
                                .fill(Color(red: 0.2, green: 0.68, blue: 1.0))
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.0, isoFetcher.downloadProgress)))), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var isoStatusBadgeColor: Color {
        if isoFetcher.isDownloading {
            return Color(red: 0.25, green: 0.72, blue: 1.0)
        } else if isoFetcher.hasBuiltInISO {
            return isoFetcher.hasUpdateAvailable ? .orange : .green
        } else {
            return .orange
        }
    }

    private var isoStatusBadgeText: String {
        if isoFetcher.isDownloading {
            return "正在获取"
        } else if isoFetcher.hasBuiltInISO {
            return isoFetcher.hasUpdateAvailable ? "可更新" : "已内置"
        } else {
            return "未获取"
        }
    }

    private func settingRow(title: String, desc: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .green))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - 数据存储空间与位置 (支持外置硬盘文件夹与自定义容量上限)
    private var storageManagementSection: some View {
        let sizeOptions = [128, 256, 512, 1024, 2048]
        let isExternal = dataStorageDirectory.hasPrefix("/Volumes/")
        let displayDir = dataStorageDirectory.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let freeSpaceInfo = availableVolumeSpaceText(for: dataStorageDirectory)

        return VStack(alignment: .leading, spacing: 6) {
            Text("数据存储空间与位置")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.45))

            VStack(alignment: .leading, spacing: 9) {
                // 第一行：存储位置与「更改位置」按钮
                HStack(spacing: 10) {
                    Image(systemName: isExternal ? "externaldrive.fill.badge.checkmark" : "internaldrive.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 6) {
                            Text(isExternal ? "外置硬盘存储目录" : "本地数据存储目录")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            if !freeSpaceInfo.isEmpty {
                                Text(freeSpaceInfo)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.15))
                                    )
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        Text(displayDir)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.52))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)

                    Button(action: chooseDataStorageFolder) {
                        HStack(spacing: 3.5) {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("更改目录")
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // 第二行：飞牛存储空间识别的数据盘容量上限 (稀疏文件按实际存入占用)
                HStack(spacing: 6) {
                    Text("虚拟盘容量上限 (按需占用):")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.white.opacity(0.52))
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 5) {
                        ForEach(sizeOptions, id: \.self) { size in
                            capacityButton(for: size)
                        }
                    }
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func capacityButton(for size: Int) -> some View {
        let isSelected = (dataDiskSizeGB == size)
        let label = size >= 1024 ? "\(size / 1024)TB" : "\(size)G"
        let weight: Font.Weight = isSelected ? .bold : .medium
        let fgColor: Color = isSelected ? .white : Color.white.opacity(0.6)
        let bgColor: Color = isSelected ? Color.orange.opacity(0.85) : Color.white.opacity(0.06)

        return Button(action: {
            dataDiskSizeGB = size
        }) {
            Text(label)
                .font(.system(size: 10, weight: weight, design: .monospaced))
                .lineLimit(1)
                .foregroundColor(fgColor)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(bgColor)
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func availableVolumeSpaceText(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
            let freeBytes = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            if freeBytes > 0 {
                let freeGB = Int(freeBytes / (1024 * 1024 * 1024))
                return "可用 \(freeGB) GB"
            }
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
           let freeSize = attrs[.systemFreeSize] as? NSNumber {
            let freeGB = Int(freeSize.int64Value / (1024 * 1024 * 1024))
            return "可用 \(freeGB) GB"
        }
        return ""
    }

    private func chooseDataStorageFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择飞牛 fnOS 数据存储文件夹（可选择外置硬盘目录）"
        panel.prompt = "设为存储目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if FileManager.default.fileExists(atPath: dataStorageDirectory) {
            panel.directoryURL = URL(fileURLWithPath: dataStorageDirectory)
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        }
        if panel.runModal() == .OK, let selectedURL = panel.url {
            dataStorageDirectory = selectedURL.path
        }
    }

    private func parseForwardedPorts(_ text: String) -> [Int] {
        let separators = CharacterSet(charactersIn: ",，;； \n\t")
        return Array(Set(text.components(separatedBy: separators)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { (1...65535).contains($0) && $0 != vmManager.settings.webPort }))
            .sorted()
    }

    private func saveAndDismiss() {
        var s = vmManager.settings
        let oldDataDir = s.dataStorageDirectory
        let storageChanged = (oldDataDir != dataStorageDirectory) || (s.dataDiskSizeGB != dataDiskSizeGB)

        if isoFetcher.hasBuiltInISO {
            s.isoPath = isoFetcher.builtInISOPath
            s.attachISO = true
        } else {
            s.isoPath = ""
        }
        s.dataStorageDirectory = dataStorageDirectory
        s.dataDiskSizeGB = dataDiskSizeGB
        s.customDomainPrefix = domainPrefix.trimmingCharacters(in: .whitespaces).isEmpty ? "nas" : domainPrefix.trimmingCharacters(in: .whitespaces)
        s.isCustomDomainEnabled = isDomainEnabled
        s.autoStartOnLogin = autoStart
        s.dynamicOptimization = dynamicBallooning
        s.lanAccessEnabled = lanAccessEnabled
        s.lanForwardedPorts = parseForwardedPorts(lanForwardedPortsText)
        vmManager.updateSettings(s)

        if isDomainEnabled {
            let targetIP = vmManager.currentIP ?? "192.168.64.2"
            HostsManager.shared.updateDomainMapping(prefix: s.customDomainPrefix, targetIP: targetIP) { _ in }
        } else {
            HostsManager.shared.removeDomainMapping { _ in }
        }

        if storageChanged {
            vmManager.migrateAndApplyStorage(from: oldDataDir, to: dataStorageDirectory, sizeGB: dataDiskSizeGB)
        }

        dismiss()
    }
}

// MARK: - 「运行日志」独立窗口视图 (实时滚动显示虚拟化与引导日志 + 可选切换引导画面)
public struct LogViewerWindowView: View {
    @ObservedObject public var vmManager: VMManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0 // 0: 实时日志, 1: 引导画面
    @State private var autoScroll: Bool = true
    @State private var didCopy: Bool = false

    public init(vmManager: VMManager) {
        self.vmManager = vmManager
    }

    public var body: some View {
        ZStack(alignment: .top) {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color(red: 0.08, green: 0.09, blue: 0.13, opacity: 0.95)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 顶部标题栏 (与主界面标题高度对齐，无横线分隔)
                ZStack {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.blue)

                        Text("FnOS 运行日志")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 6) {
                        Spacer()

                        // 视图模式切换胶囊 (日志流 / 引导画面)
                        HStack(spacing: 2) {
                            tabPillButton(title: "实时日志", icon: "list.bullet.rectangle", tag: 0)
                            tabPillButton(title: "引导画面", icon: "display", tag: 1)
                        }
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
                .frame(height: 38)
                .padding(.top, 10)
                .padding(.horizontal, 14)

                // 2. 当前状态摘要栏
                HStack(spacing: 9) {
                    if vmManager.status == .installing || vmManager.status == .starting || vmManager.status == .stopping {
                        SpinningStatusRing(color: statusAccentColor, size: 13)
                    } else {
                        Circle()
                            .fill(statusAccentColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: statusAccentColor.opacity(0.7), radius: 4)
                    }

                    Text(vmManager.status.rawValue)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)

                    if (vmManager.status == .installing || vmManager.status == .starting) && vmManager.bootingElapsedSeconds > 0 {
                        Text(formatElapsed(vmManager.bootingElapsedSeconds))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.95))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.14))
                            )
                    }

                    Spacer()

                    if vmManager.status == .installing {
                        Button(action: {
                            vmManager.markInstalledAndRestart()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "opticaldiscdrive")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text("弹出光盘重启")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.green.opacity(0.14))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("安装向导完成后点击弹出 ISO 并从虚拟硬盘重启")

                        Button(action: {
                            vmManager.stopVM(force: true)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("停止引导")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red.opacity(0.14))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("共 \(vmManager.logEntries.count) 条记录")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.42))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))
                )
                .padding(.horizontal, 14)
                .padding(.top, 4)

                // 3. 主体区域：实时日志列表 或 虚拟机引导画面
                if selectedTab == 0 {
                    logListSection
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                } else {
                    consoleDisplaySection
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }

                // 4. 底部工具栏 (无横线分隔)
                HStack(spacing: 8) {
                    if selectedTab == 0 {
                        Toggle(isOn: $autoScroll) {
                            Text("自动滚动到底部")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.65))
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)

                        Button(action: copyAllLogs) {
                            HStack(spacing: 4) {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(didCopy ? "已复制" : "复制日志")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(didCopy ? .green : Color.white.opacity(0.75))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            vmManager.clearLogs()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("清空")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color.white.opacity(0.65))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("提示：首次安装可在引导画面内按方向键与回车完成图形/文本向导")
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: { dismiss() }) {
                        Text("关闭")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.blue.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MiniWindowConfigurator(targetSize: NSSize(width: 490, height: 430)))
        .preferredColorScheme(.dark)
    }

    // MARK: - 实时日志滚动列表
    private var logListSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(vmManager.logEntries) { entry in
                        HStack(alignment: .top, spacing: 7) {
                            Text(entry.timestamp)
                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.38))
                                .frame(width: 54, alignment: .leading)

                            Text(entry.tag)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(tagColor(for: entry))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(tagColor(for: entry).opacity(0.15))
                                )

                            Text(entry.message)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(messageColor(for: entry))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.02))
                        )
                        .id(entry.id)
                    }
                }
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.38))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .onChange(of: vmManager.logEntries.count) { _, _ in
                if autoScroll, let lastId = vmManager.logEntries.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let lastId = vmManager.logEntries.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 引导画面视图 (内嵌 Virtualization 图形显示窗口)
    private var consoleDisplaySection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.55))

            if let vm = vmManager.vzVirtualMachine,
               vmManager.status.isRunningOrStarting {
                VMConsoleView(virtualMachine: vm)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(Color.white.opacity(0.35))
                    Text("当前虚拟引擎未启动，暂无引导画面")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                    Text("点击主界面「启动」后可在此实时查看 UEFI / GRUB 引导输出")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func tabPillButton(title: String, icon: String, tag: Int) -> some View {
        Button(action: {
            selectedTab = tag
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(selectedTab == tag ? .white : Color.white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 5.5)
                    .fill(selectedTab == tag ? Color.blue.opacity(0.75) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusAccentColor: Color {
        switch vmManager.status {
        case .running: return .green
        case .starting, .stopping, .installing: return .orange
        case .paused: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private func tagColor(for entry: VMLogEntry) -> Color {
        switch entry.level {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .info:
            switch entry.tag {
            case "引导", "UEFI", "BOOT": return .cyan
            case "内核", "串口", "KERNEL", "SERIAL": return .purple
            case "存储", "镜像", "STORAGE", "ISO": return .blue
            case "网络", "NET", "READY": return .mint
            default: return .blue
            }
        }
    }

    private func messageColor(for entry: VMLogEntry) -> Color {
        switch entry.level {
        case .success: return Color(red: 0.45, green: 0.95, blue: 0.60)
        case .warning: return Color(red: 1.0, green: 0.80, blue: 0.40)
        case .error: return Color(red: 1.0, green: 0.45, blue: 0.45)
        case .info: return Color.white.opacity(0.86)
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func copyAllLogs() {
        let text = vmManager.logEntries.map { "[\($0.timestamp)] [\($0.tag)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopy = false
        }
    }
}

