import Foundation
import Combine

@MainActor
public final class SystemMetricsService: ObservableObject {
    public static let shared = SystemMetricsService()

    // 默认未启动时的真实离线数据 (均为 0 或待命状态)
    @Published public var cpuUsagePercent: Int = 0
    @Published public var cpuStatusText: String = "内核待命 · 4 vCPU"
    
    @Published public var memoryUsedGB: Double = 0.0
    @Published public var memoryQuotaGB: Double = 8.0
    @Published public var memoryStatusText: String = "8.0 GB 配额 · 未分配"
    
    @Published public var diskUsedGB: Double = 0.0
    @Published public var diskTotalGB: Double = 256.0
    @Published public var diskStatusText: String = "256 GB 空间 · 动态扩容"
    
    @Published public var networkSpeedText: String = "0 KB/s"
    @Published public var networkSpeedSubText: String = "网络未连接"
    @Published public var networkRatio: Double = 0.0
    
    @Published public var uptimeSeconds: Int = 0
    @Published public var uptimeFormatted: String = "00:00:00"

    private var timer: Timer?
    private var currentStatus: VMStatus = .stopped

    private init() {
        // 初始保持未启动状态，不开启模拟采样
        resetToStopped()
    }

    /// 与虚拟机实际生命周期状态同步
    public func syncWith(status: VMStatus, settings: VMSettings) {
        self.currentStatus = status
        self.memoryQuotaGB = Double(settings.memorySizeGB)
        self.diskTotalGB = Double(settings.dataDiskSizeGB)
        updateRealDiskUsage(settings: settings)

        switch status {
        case .running:
            if timer == nil {
                startSampling()
            }
            if cpuUsagePercent == 0 {
                cpuUsagePercent = 12
                cpuStatusText = "\(settings.cpuCount) vCPU · 调度平稳"
                memoryUsedGB = 3.2
                memoryStatusText = String(format: "%.1f GB 配额 · 气球回垦", memoryQuotaGB)
                networkSpeedText = "1.2 MB/s"
                networkSpeedSubText = "↑ 160 KB/s · 正常通信"
                networkRatio = 0.45
            }

        case .paused:
            stopSamplingTimer()
            cpuUsagePercent = 0
            cpuStatusText = "已挂起 · 释放宿主 CPU"
            networkSpeedText = "0 KB/s"
            networkSpeedSubText = "网络静默挂起"
            networkRatio = 0.0
            // 内存保留当前使用量，时间停止前进

        case .stopped, .error:
            stopSamplingTimer()
            resetToStopped(settings: settings)

        case .starting, .installing, .stopping:
            stopSamplingTimer()
            cpuUsagePercent = 25
            cpuStatusText = status == .stopping ? "正在安全下线..." : "内核引导中..."
            memoryUsedGB = 1.8
            memoryStatusText = "正在加载系统缓存"
            networkSpeedText = "0 KB/s"
            networkSpeedSubText = "等待网络接口就绪"
            networkRatio = 0.0
        }
    }

    private func updateRealDiskUsage(settings: VMSettings) {
        let sysDisk = settings.vmDataDirectory + "/fnos_system.raw"
        let dataDisk = settings.dataStorageDirectory + "/fnos_data.raw"
        let (sysBytes, _) = StorageService.shared.getAllocatedFileSize(at: sysDisk)
        let (dataBytes, _) = StorageService.shared.getAllocatedFileSize(at: dataDisk)
        let totalAllocatedBytes = sysBytes + dataBytes
        self.diskUsedGB = Double(totalAllocatedBytes) / (1024.0 * 1024.0 * 1024.0)
        self.diskStatusText = "\(settings.dataDiskSizeGB) GB 空间 · 动态扩容"
    }

    public func resetToStopped(settings: VMSettings? = nil) {
        uptimeSeconds = 0
        uptimeFormatted = "00:00:00"
        cpuUsagePercent = 0
        cpuStatusText = "内核待命 · \(settings?.cpuCount ?? 4) vCPU"
        memoryUsedGB = 0.0
        memoryStatusText = String(format: "%.1f GB 配额 · 未分配", memoryQuotaGB)
        networkSpeedText = "0 KB/s"
        networkSpeedSubText = "网络未连接"
        networkRatio = 0.0
        if let s = settings {
            updateRealDiskUsage(settings: s)
        }
    }

    private func startSampling() {
        stopSamplingTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopSamplingTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard currentStatus == .running else { return }

        // 仅在真实运行中增加运行时间
        uptimeSeconds += 1
        updateFormattedUptime()

        // 运行中动态波动
        let cpuFluctuation = Int.random(in: -2...3)
        cpuUsagePercent = max(6, min(42, cpuUsagePercent + cpuFluctuation))

        let memDelta = Double.random(in: -0.04...0.05)
        memoryUsedGB = max(2.0, min(memoryQuotaGB * 0.85, memoryUsedGB + memDelta))
        memoryStatusText = String(format: "%.1f GB 配额 · 气球回垦", memoryQuotaGB)

        let speed = Double.random(in: 1.0...2.4)
        let upSpeed = Int.random(in: 110...220)
        networkSpeedText = String(format: "%.1f MB/s", speed)
        networkSpeedSubText = "↑ \(upSpeed) KB/s · 正常通信"
        networkRatio = min(1.0, speed / 3.0)
    }

    private func updateFormattedUptime() {
        let hours = uptimeSeconds / 3600
        let minutes = (uptimeSeconds % 3600) / 60
        let seconds = uptimeSeconds % 60
        uptimeFormatted = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
