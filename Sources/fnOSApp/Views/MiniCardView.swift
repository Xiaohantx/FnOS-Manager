import SwiftUI
import AppKit

public struct MiniCardView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var vmManager = VMManager.shared
    @ObservedObject var metrics = SystemMetricsService.shared

    @State private var showResetConfirmation = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            // 1. macOS 原生毛玻璃背景
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // 2. 深色高质感半透明底色
            Color(red: 0.08, green: 0.09, blue: 0.13, opacity: 0.92)
                .ignoresSafeArea()

            // 3. 卡片主内容 (严谨贴合，无多余上下留白)
            VStack(spacing: 0) {
                // 顶栏 (ZStack 确保品牌在全卡片绝对水平居中，并与左侧交通灯、右侧按钮严格垂直居中)
                titleBar

                // 核心状态横幅
                statusBanner
                    .padding(.horizontal, 14)
                    .padding(.top, 7)
                    .padding(.bottom, 12)

                // 4 格核心资源监控卡片 (2x2 网格)
                metricsGrid
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                // 核心双控制按键 (启动/暂停合一 + 重置二次确认)
                actionButtons
                    .padding(.horizontal, 14)

                Spacer(minLength: 6)
                    .frame(maxHeight: 12)

                // 底部微状态与官网链接 (灰色贴底边，无分割横线)
                footerBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 4. 重置二次确认模态弹窗 (高斯模糊置顶层)
            if showResetConfirmation {
                ResetConfirmModalView(
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showResetConfirmation = false
                        }
                    },
                    onConfirm: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showResetConfirmation = false
                        }
                        vmManager.resetVM()
                    }
                )
                .zIndex(100)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(MiniWindowConfigurator())
        .preferredColorScheme(.dark)
        .onAppear {
            AppWindowManager.shared.setupMenuAndObservers(
                openAbout: { openWindow(id: "about-window") },
                openSettings: { openWindow(id: "settings-window") },
                openLogs: { openWindow(id: "log-window") }
            )
            metrics.syncWith(status: vmManager.status, settings: vmManager.settings)
        }
        .onChange(of: vmManager.status) { _, newStatus in
            metrics.syncWith(status: newStatus, settings: vmManager.settings)
        }
    }

    private var isTransitioningStatus: Bool {
        vmManager.status == .installing || vmManager.status == .starting || vmManager.status == .stopping
    }

    private var canResetVM: Bool {
        vmManager.status == .running || vmManager.status == .paused
    }

    // MARK: - 顶栏 (ZStack 绝对居中 + 严格水平基准线)
    private var titleBar: some View {
        ZStack {
            // 1. 绝对居中的品牌与标题 (位于卡片正中心)
            HStack(spacing: 6.5) {
                LogoBadgeView(size: 19)

                Text("FnOS Manager")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }

            // 2. 右侧操作按钮 (查看日志 + 偏好设置)
            HStack(spacing: 6) {
                Spacer()

                Button(action: {
                    openWindow(id: "log-window")
                }) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(isTransitioningStatus ? Color.orange : Color.white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("查看运行日志")

                Button(action: {
                    openWindow(id: "settings-window")
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("偏好设置")
            }
        }
        .frame(height: 38)
        .offset(y: -3.3)
        .padding(.horizontal, 14)
    }

    // MARK: - 运行状态横幅 (带动态 Loading 环、实时最新日志与「日志」快捷入口)
    private var statusBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            // 状态指示灯：引导/启动/关机中显示旋转 Loading 动效，其余显示状态圆点
            if isTransitioningStatus {
                SpinningStatusRing(color: statusIndicatorColor, size: 15)
                    .frame(width: 15, height: 15)
            } else {
                Circle()
                    .fill(statusIndicatorColor)
                    .frame(width: 8.5, height: 8.5)
                    .shadow(color: statusIndicatorColor.opacity(vmManager.status == .running ? 0.7 : 0.0), radius: 4, x: 0, y: 0)
            }

            // 状态文字与最新日志/访问端点 (严格单行不折行)
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(statusTitleText)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if vmManager.status == .installing || vmManager.status == .starting {
                        Text(String(format: "%02d:%02d", vmManager.bootingElapsedSeconds / 60, vmManager.bootingElapsedSeconds % 60))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Color.orange)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(statusSubtitleText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(isTransitioningStatus ? Color(red: 1.0, green: 0.78, blue: 0.42) : Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture {
                        if vmManager.status == .running, let url = vmManager.webConsoleURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
            }

            Spacer(minLength: 4)

            // 右侧快捷操作胶囊：「日志」+「控制台」
            HStack(spacing: 6) {
                Button(action: {
                    openWindow(id: "log-window")
                }) {
                    HStack(spacing: 3.5) {
                        Image(systemName: "terminal")
                            .font(.system(size: 9, weight: .semibold))
                        Text("日志")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isTransitioningStatus ? Color(red: 1.0, green: 0.82, blue: 0.4) : Color.white.opacity(0.85))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isTransitioningStatus ? Color.orange.opacity(0.16) : Color.white.opacity(0.07))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isTransitioningStatus ? Color.orange.opacity(0.35) : Color.white.opacity(0.13), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("查看最新实时日志与安装引导画面")

                Button(action: {
                    guard vmManager.status == .running else { return }
                    if let url = vmManager.webConsoleURL {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 3.5) {
                        Text("控制台")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundColor(vmManager.status == .running ? Color.white.opacity(0.9) : Color.white.opacity(0.32))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(vmManager.status == .running ? 0.08 : 0.03))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(vmManager.status == .running ? 0.14 : 0.05), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(vmManager.status != .running)
                .help(vmManager.status == .running ? "在默认浏览器中打开控制台" : "等待系统完成引导后可用")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isTransitioningStatus ? Color.orange.opacity(0.22) : Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - 4格核心资源监控卡片 (舒适开阔，带呼吸感)
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 10) {
            // Tile 1: CPU
            metricTile(
                iconName: "cpu",
                iconColor: Color(red: 0.1, green: 0.6, blue: 1.0),
                title: "CPU 负载",
                value: "\(metrics.cpuUsagePercent)%",
                progress: Double(metrics.cpuUsagePercent) / 100.0,
                progressColor: Color(red: 0.1, green: 0.6, blue: 1.0),
                subText: metrics.cpuStatusText
            )

            // Tile 2: 内存
            metricTile(
                iconName: "memorychip",
                iconColor: Color(red: 0.2, green: 0.85, blue: 0.45),
                title: "内存动态",
                value: String(format: "%.1f GB", metrics.memoryUsedGB),
                progress: metrics.memoryQuotaGB > 0 ? min(1.0, metrics.memoryUsedGB / metrics.memoryQuotaGB) : 0,
                progressColor: Color(red: 0.2, green: 0.85, blue: 0.45),
                subText: metrics.memoryStatusText
            )

            // Tile 3: 存储
            metricTile(
                iconName: "internaldrive",
                iconColor: Color(red: 1.0, green: 0.65, blue: 0.1),
                title: "数据存储",
                value: String(format: "%.1f GB", metrics.diskUsedGB),
                progress: min(1.0, metrics.diskUsedGB / metrics.diskTotalGB),
                progressColor: Color(red: 1.0, green: 0.65, blue: 0.1),
                subText: metrics.diskStatusText
            )

            // Tile 4: 网络流速
            metricTile(
                iconName: "network",
                iconColor: Color(red: 0.75, green: 0.4, blue: 0.95),
                title: "实时流速",
                value: metrics.networkSpeedText,
                progress: metrics.networkRatio,
                progressColor: Color(red: 0.75, green: 0.4, blue: 0.95),
                subText: metrics.networkSpeedSubText
            )
        }
    }

    private func metricTile(
        iconName: String,
        iconColor: Color,
        title: String,
        value: String,
        progress: Double,
        progressColor: Color,
        subText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(vmManager.status == .running ? iconColor : Color.white.opacity(0.35))

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
                    .lineLimit(1)

                Spacer()

                Text(value)
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(vmManager.status == .running ? .white : Color.white.opacity(0.5))
                    .lineLimit(1)
            }

            // 细致进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3.8)

                    Capsule()
                        .fill(vmManager.status == .running ? progressColor : Color.white.opacity(0.15))
                        .frame(width: max(3.8, geo.size.width * CGFloat(min(1.0, max(0.0, progress)))), height: 3.8)
                }
            }
            .frame(height: 3.8)

            // 说明文字 (强制单行不折行)
            Text(subText)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.46))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - 核心双操作按键 (启动/暂停/引导Loading合一 + 重置)
    private var actionButtons: some View {
        HStack(spacing: 9) {
            // 按钮 1: 根据当前状态显示「启动 / 引导中 Loading / 暂停 / 继续」
            Button(action: {
                guard !isTransitioningStatus else { return }
                vmManager.togglePlayPause()
            }) {
                HStack(spacing: 6) {
                    switch vmManager.status {
                    case .installing:
                        SpinningStatusRing(color: Color.orange, size: 13)
                        Text("安装引导中...")
                            .font(.system(size: 12.5, weight: .semibold))
                    case .starting:
                        SpinningStatusRing(color: Color.orange, size: 13)
                        Text("正在启动...")
                            .font(.system(size: 12.5, weight: .semibold))
                    case .stopping:
                        SpinningStatusRing(color: Color.orange, size: 13)
                        Text("正在关机...")
                            .font(.system(size: 12.5, weight: .semibold))
                    case .running:
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11.5, weight: .bold))
                        Text("暂停")
                            .font(.system(size: 13, weight: .semibold))
                    case .paused:
                        Image(systemName: "play.fill")
                            .font(.system(size: 11.5, weight: .bold))
                        Text("继续")
                            .font(.system(size: 13, weight: .semibold))
                    case .stopped, .error:
                        Image(systemName: "play.fill")
                            .font(.system(size: 11.5, weight: .bold))
                        Text("启动")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundColor(isTransitioningStatus ? Color(red: 1.0, green: 0.82, blue: 0.42) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Group {
                        if isTransitioningStatus {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.orange.opacity(0.12))
                        } else if vmManager.status == .running {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.22, green: 0.85, blue: 0.42), Color(red: 0.16, green: 0.72, blue: 0.35)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isTransitioningStatus
                                ? Color.orange.opacity(0.28)
                                : (vmManager.status == .running ? Color.white.opacity(0.12) : Color.clear),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: (vmManager.status == .running || isTransitioningStatus) ? Color.clear : Color.green.opacity(0.3),
                    radius: 5,
                    x: 0,
                    y: 2
                )
            }
            .buttonStyle(.plain)
            .disabled(isTransitioningStatus)

            // 按钮 2: 重置按钮 (安装引导中/未启动时禁用置灰，运行/挂起时可用)
            Button(action: {
                guard canResetVM else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showResetConfirmation = true
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("重置")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(canResetVM ? Color.white.opacity(0.85) : Color.white.opacity(0.28))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(canResetVM ? 0.06 : 0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(canResetVM ? 0.10 : 0.05), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canResetVM)
            .help(canResetVM ? "强制重启虚拟机" : (isTransitioningStatus ? "安装引导进行中，暂不可重置" : "虚拟机未启动"))
        }
    }

    // MARK: - 底部轻量微状态与官网链接 (灰色纯文字贴底)
    private var footerBar: some View {
        HStack {
            // 调度引擎状态 (纯灰色)
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                Text(engineStatusText)
                    .font(.system(size: 9.5))
            }
            .foregroundColor(Color.white.opacity(0.38))

            Spacer()

            // 官网链接 (纯灰色文字与外链小箭头，无背景外框)
            Link(destination: URL(string: "https://fnnas.com/")!) {
                HStack(spacing: 2.5) {
                    Image(systemName: "network")
                        .font(.system(size: 8))
                    Text("fnnas.com")
                        .font(.system(size: 9.5))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 7))
                }
                .foregroundColor(Color.white.opacity(0.38))
            }
            .buttonStyle(.plain)
            .help("访问飞牛私有云官方网站")

            Spacer()

            // 运行时间计数 (纯灰色)
            Text(metrics.uptimeFormatted)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.38))
        }
    }

    // MARK: - 计算属性
    private var statusIndicatorColor: Color {
        switch vmManager.status {
        case .running: return Color(red: 0.2, green: 0.85, blue: 0.4)
        case .paused: return Color(red: 1.0, green: 0.75, blue: 0.1)
        case .starting, .installing, .stopping: return Color.orange
        case .stopped: return Color.gray.opacity(0.6)
        case .error: return Color.red
        }
    }

    private var statusTitleText: String {
        switch vmManager.status {
        case .running: return "虚拟系统运行中"
        case .paused: return "虚拟系统已挂起暂停"
        case .starting: return "虚拟系统启动中..."
        case .installing: return "安装引导中..."
        case .stopping: return "正在关机..."
        case .stopped: return "虚拟系统未启动"
        case .error: return "运行异常"
        }
    }

    private var statusSubtitleText: String {
        switch vmManager.status {
        case .running:
            return vmManager.formattedAccessAddress
        case .paused:
            let domain = "\(vmManager.settings.customDomainPrefix).fnos"
            return "已释放宿主 CPU · \(domain)"
        case .installing, .starting, .stopping:
            return vmManager.latestLogLine
        case .error:
            return vmManager.errorMessage ?? vmManager.latestLogLine
        case .stopped:
            return "就绪 · 点击启动"
        }
    }

    private var engineStatusText: String {
        switch vmManager.status {
        case .running: return "自适应调度生效"
        case .paused: return "内核休眠待机"
        case .stopped: return "待命就绪"
        case .installing: return "UEFI 安装引导中"
        case .starting: return "内核启动中"
        case .stopping: return "正在释放资源"
        case .error: return "服务异常"
        }
    }
}

// MARK: - 丝滑恒速旋转 Loading 指示环 (基于 TimelineView，不受视图重排影响)
public struct SpinningStatusRing: View {
    public var color: Color = .orange
    public var size: CGFloat = 14

    public init(color: Color = .orange, size: CGFloat = 14) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360.0
            ZStack {
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1.8)
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0.0, to: 0.68)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(angle))

                Circle()
                    .fill(color)
                    .frame(width: size * 0.34, height: size * 0.34)
            }
        }
    }
}

// MARK: - 极简小卡片窗口配置器 (恒定卡片尺寸，彻底切断放大与缩放)
struct MiniWindowConfigurator: NSViewRepresentable {
    var targetSize: NSSize = NSSize(width: 390, height: 350)
    var title: String = "FnOS Manager"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            
            // 1. 标题栏隐藏与原生透明融合
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.remove(.resizable)
            window.collectionBehavior = [.fullScreenNone]
            
            // 2. 隐藏并禁用缩放按钮
            if let zoomButton = window.standardWindowButton(.zoomButton) {
                zoomButton.isHidden = true
                zoomButton.isEnabled = false
            }
            
            // 3. 毛玻璃透明背景与自由拖拽
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.title = self.title
            
            // 4. 窗口内外尺寸严格锁死
            window.setContentSize(self.targetSize)
            window.minSize = self.targetSize
            window.maxSize = self.targetSize
            
            // 5. Runtime 彻底替换 zoom 与 performZoom 为空实现 (100% 阻断任何缩放请求)
            suppressWindowZoom(for: window)
            
            // 6. 同步左上角主菜单栏配置
            AppWindowManager.shared.configureMainMenu()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            AppWindowManager.shared.configureMainMenu()
        }
    }

    private func suppressWindowZoom(for window: NSWindow) {
        let windowClass: AnyClass = type(of: window)
        let noopBlock: @convention(block) (AnyObject, Any?) -> Void = { _, _ in }
        let newImp = imp_implementationWithBlock(noopBlock)

        if let mZoom = class_getInstanceMethod(windowClass, #selector(NSWindow.zoom(_:))) {
            method_setImplementation(mZoom, newImp)
        }
        if let mPerformZoom = class_getInstanceMethod(windowClass, #selector(NSWindow.performZoom(_:))) {
            method_setImplementation(mPerformZoom, newImp)
        }
    }
}
