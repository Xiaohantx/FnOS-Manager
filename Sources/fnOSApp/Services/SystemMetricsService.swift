import Foundation
import Combine
import Darwin

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
    private var lastIBytes: UInt64 = 0
    private var lastOBytes: UInt64 = 0
    private var hasNetworkBaseline: Bool = false

    private init() {
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
            let initialCPU = Int(round(getProcessCPU()))
            self.cpuUsagePercent = initialCPU
            self.cpuStatusText = "\(settings.cpuCount) vCPU · 调度平稳"
            if let memMB = getProcessResidentMemoryMB() {
                self.memoryUsedGB = memMB / 1024.0
            }
            self.memoryStatusText = String(format: "%.1f GB 配额 · 气球回垦", memoryQuotaGB)
            self.networkSpeedText = "0 KB/s"
            self.networkSpeedSubText = "链路就绪"
            self.networkRatio = 0.0

        case .paused:
            stopSamplingTimer()
            cpuUsagePercent = 0
            cpuStatusText = "已挂起 · 释放宿主 CPU"
            networkSpeedText = "0 KB/s"
            networkSpeedSubText = "网络静默挂起"
            networkRatio = 0.0

        case .stopped, .error:
            stopSamplingTimer()
            resetToStopped(settings: settings)

        case .starting, .installing, .stopping:
            stopSamplingTimer()
            cpuUsagePercent = 20
            cpuStatusText = status == .stopping ? "正在安全下线..." : "内核引导中..."
            memoryUsedGB = min(1.8, memoryQuotaGB * 0.3)
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
        hasNetworkBaseline = false
        lastIBytes = 0
        lastOBytes = 0
        if let s = settings {
            updateRealDiskUsage(settings: s)
        }
    }

    private func startSampling() {
        stopSamplingTimer()
        hasNetworkBaseline = false
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

        // 1. 运行时间自然累计
        uptimeSeconds += 1
        updateFormattedUptime()

        // 2. 真实采样虚拟网卡 (bridge100) 吞吐流速
        let net = sampleRealNetworkSpeed()
        self.networkSpeedText = net.speedText
        self.networkSpeedSubText = net.subText
        self.networkRatio = net.ratio

        // 3. 采样真实进程 CPU 与内存占用
        let realCPU = getProcessCPU()
        let targetCPU = max(2, min(95, Int(round(realCPU))))
        // 平滑过渡
        self.cpuUsagePercent = (self.cpuUsagePercent * 3 + targetCPU) / 4
        if self.cpuUsagePercent < 15 {
            self.cpuStatusText = "\(VMManager.shared.settings.cpuCount) vCPU · 低功耗空闲"
        } else if self.cpuUsagePercent < 50 {
            self.cpuStatusText = "\(VMManager.shared.settings.cpuCount) vCPU · 调度平稳"
        } else {
            self.cpuStatusText = "\(VMManager.shared.settings.cpuCount) vCPU · 高负载运行"
        }

        // 4. 真实物理常驻内存 (读取进程在 macOS 宿主机实际占用的 RSS 内存)
        if let residentMB = getProcessResidentMemoryMB() {
            let usedGB = residentMB / 1024.0
            self.memoryUsedGB = (self.memoryUsedGB * 3.0 + usedGB) / 4.0
        }
        self.memoryStatusText = String(format: "%.1f GB 配额 · 气球回垦", memoryQuotaGB)
    }

    // MARK: - 真实网络接口吞吐采样 (基于 Darwin getifaddrs 统计 bridge 接口字节差)
    private func sampleRealNetworkSpeed() -> (speedText: String, subText: String, ratio: Double) {
        guard let current = fetchBridgeBytes() else {
            return ("0 KB/s", "空闲待机 · 正常连接", 0.0)
        }

        guard hasNetworkBaseline else {
            lastIBytes = current.ibytes
            lastOBytes = current.obytes
            hasNetworkBaseline = true
            return ("0 KB/s", "链路就绪", 0.0)
        }

        let deltaIn = current.ibytes >= lastIBytes ? (current.ibytes - lastIBytes) : 0
        let deltaOut = current.obytes >= lastOBytes ? (current.obytes - lastOBytes) : 0
        lastIBytes = current.ibytes
        lastOBytes = current.obytes

        let totalBytes = deltaIn + deltaOut
        let speedStr = formatSpeed(bytesPerSec: totalBytes)
        let subStr: String

        if totalBytes < 50 * 1024 {
            subStr = "空闲待机 · 正常连接"
        } else {
            subStr = "↓ \(formatSpeed(bytesPerSec: deltaIn)) · ↑ \(formatSpeed(bytesPerSec: deltaOut))"
        }

        // 进度条比例：按 30 MB/s 满刻度线性映射
        let ratio = min(1.0, Double(totalBytes) / (30.0 * 1024.0 * 1024.0))
        return (speedStr, subStr, ratio)
    }

    private func fetchBridgeBytes() -> (ibytes: UInt64, obytes: UInt64)? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var found = false

        while let cur = ptr {
            let name = String(cString: cur.pointee.ifa_name)
            // 匹配 macOS Virtualization 虚拟网桥接口 (通常为 bridge100, bridge101 或当前活动的物理/虚拟桥)
            if (name.hasPrefix("bridge10") || name == "bridge100"),
               cur.pointee.ifa_addr != nil,
               cur.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = cur.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self)
                    totalIn += UInt64(ifData.pointee.ifi_ibytes)
                    totalOut += UInt64(ifData.pointee.ifi_obytes)
                    found = true
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return found ? (totalIn, totalOut) : nil
    }

    private func formatSpeed(bytesPerSec: UInt64) -> String {
        if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1f MB/s", Double(bytesPerSec) / (1024.0 * 1024.0))
        } else if bytesPerSec >= 1024 {
            return String(format: "%d KB/s", bytesPerSec / 1024)
        } else {
            return "\(bytesPerSec) B/s"
        }
    }

    // MARK: - 真实虚拟机进程 (com.apple.Virtualization.VirtualMachine.xpc) PID 自动发现
    private var cachedVMPid: pid_t? = nil
    private var lastVMCPUTime: UInt64 = 0
    private var lastVMSampleDate = Date()

    private func getVirtualMachinePID() -> pid_t? {
        if let pid = cachedVMPid, kill(pid, 0) == 0 {
            return pid
        }
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.stride)
        let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, count)
        guard bytesUsed > 0 else { return nil }

        let pathBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: 4096)
        defer { pathBuffer.deallocate() }

        let myUID = getuid()
        for pid in pids where pid > 0 {
            var bsdInfo = proc_bsdinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
            if ret > 0 && bsdInfo.pbi_uid == myUID {
                let pathLen = proc_pidpath(pid, pathBuffer, 4096)
                if pathLen > 0 {
                    let path = String(cString: pathBuffer)
                    if path.contains("Virtualization.VirtualMachine") {
                        cachedVMPid = pid
                        return pid
                    }
                }
            }
        }
        return nil
    }

    // MARK: - 真实进程 CPU 占用采样
    private func getProcessCPU() -> Double {
        if let vmPid = getVirtualMachinePID() {
            var info = proc_taskinfo()
            let ret = withUnsafeMutablePointer(to: &info) { ptr in
                proc_pidinfo(vmPid, PROC_PIDTASKINFO, 0, ptr, Int32(MemoryLayout<proc_taskinfo>.size))
            }
            if ret > 0 {
                let now = Date()
                let dt = now.timeIntervalSince(lastVMSampleDate)
                let curCPUTime = info.pti_total_user + info.pti_total_system
                var cpu: Double = 0.0
                if lastVMCPUTime > 0 && dt > 0 {
                    let dcpu = curCPUTime > lastVMCPUTime ? (curCPUTime - lastVMCPUTime) : 0
                    cpu = (Double(dcpu) / 1_000_000_000.0) / dt * 100.0
                }
                lastVMCPUTime = curCPUTime
                lastVMSampleDate = now
                if cpu > 0.0 {
                    return cpu
                }
            }
        }

        // Fallback: 采样宿主自身线程 CPU
        var threadsList: thread_act_array_t?
        var threadsCount: mach_msg_type_number_t = 0
        let kerr = task_threads(mach_task_self_, &threadsList, &threadsCount)
        guard kerr == KERN_SUCCESS, let threads = threadsList else { return 0.0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threads),
                vm_size_t(threadsCount * UInt32(MemoryLayout<thread_t>.stride))
            )
        }

        var totalUsage: Double = 0.0
        for i in 0..<Int(threadsCount) {
            var threadInfo = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let kr = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if kr == KERN_SUCCESS {
                if (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                    totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
        }
        return totalUsage
    }

    // MARK: - 真实常驻物理内存采样
    private func getProcessResidentMemoryMB() -> Double? {
        if let vmPid = getVirtualMachinePID() {
            var info = proc_taskinfo()
            let ret = withUnsafeMutablePointer(to: &info) { ptr in
                proc_pidinfo(vmPid, PROC_PIDTASKINFO, 0, ptr, Int32(MemoryLayout<proc_taskinfo>.size))
            }
            if ret > 0 && info.pti_resident_size > 0 {
                return Double(info.pti_resident_size) / (1024.0 * 1024.0)
            }
        }

        // Fallback: 采样宿主自身常驻内存
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(taskInfo.resident_size) / (1024.0 * 1024.0)
        }
        return nil
    }

    private func updateFormattedUptime() {
        let hours = uptimeSeconds / 3600
        let minutes = (uptimeSeconds % 3600) / 60
        let seconds = uptimeSeconds % 60
        uptimeFormatted = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
