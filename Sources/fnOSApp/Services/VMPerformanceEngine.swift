import Foundation
import Virtualization
import AppKit

/// 虚拟机全生命周期动态性能调优引擎 (参考 OrbStack / Lima / Tart 虚拟化优化方案)
/// 1. VirtIO 动态内存伸缩与回垦 (Memory Ballooning via VZVirtioTraditionalMemoryBalloonDevice)
/// 2. macOS 宿主机内存压力感知 (DispatchSourceMemoryPressure)
/// 3. 前后台资源调度与功耗优化
@MainActor
public final class VMPerformanceEngine: ObservableObject {
    public static let shared = VMPerformanceEngine()

    @Published public var isBallooningActive: Bool = false
    @Published public var hostMemoryPressure: HostMemoryPressure = .normal
    @Published public var dynamicTargetMemoryGB: Double = 4.0
    @Published public var savedMemoryMB: Int = 0
    @Published public var statusDescription: String = "动态调优引擎就绪"

    public enum HostMemoryPressure: String {
        case normal = "正常"
        case warning = "偏高"
        case critical = "极高"
    }

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private weak var balloonDevice: VZVirtioTraditionalMemoryBalloonDevice?
    private var configuredMaxMemoryBytes: UInt64 = 0
    private var baseTargetMemoryBytes: UInt64 = 0
    private var isEnabled: Bool = true

    private init() {
        setupHostMemoryPressureObserver()
    }

    /// 关联运行中的虚拟机实例与内存规格
    public func attach(vm: VZVirtualMachine, configuredMemoryGB: Int, enabled: Bool = true) {
        self.isEnabled = enabled
        self.configuredMaxMemoryBytes = UInt64(configuredMemoryGB) * 1024 * 1024 * 1024
        self.baseTargetMemoryBytes = configuredMaxMemoryBytes
        self.dynamicTargetMemoryGB = Double(configuredMemoryGB)

        if let balloon = vm.memoryBalloonDevices.first as? VZVirtioTraditionalMemoryBalloonDevice {
            self.balloonDevice = balloon
            self.isBallooningActive = true
            applyMemoryTarget(self.baseTargetMemoryBytes)
            self.statusDescription = "VirtIO 内存伸缩就绪 (目标: \(configuredMemoryGB) GB)"
        } else {
            self.balloonDevice = nil
            self.isBallooningActive = false
            self.statusDescription = "未挂载气球设备"
        }
    }

    /// 解绑虚拟机
    public func detach() {
        self.balloonDevice = nil
        self.isBallooningActive = false
        self.savedMemoryMB = 0
        self.statusDescription = "虚拟机已停止"
    }

    /// 响应用户在设置面板动态修改内存配置
    public func updateConfiguredMemory(gb: Int) {
        self.configuredMaxMemoryBytes = UInt64(gb) * 1024 * 1024 * 1024
        self.baseTargetMemoryBytes = configuredMaxMemoryBytes
        self.dynamicTargetMemoryGB = Double(gb)
        applyMemoryTarget(configuredMaxMemoryBytes)
    }

    /// 监听 macOS 宿主机内核内存压力事件
    private func setupHostMemoryPressureObserver() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            if event.contains(.critical) {
                self.handleMemoryPressure(.critical)
            } else if event.contains(.warning) {
                self.handleMemoryPressure(.warning)
            } else {
                self.handleMemoryPressure(.normal)
            }
        }
        source.resume()
        self.memoryPressureSource = source
    }

    /// 根据宿主机负载动态调整气球设备目标容量，避免内存浪费与 Mac Swap 颠簸
    private func handleMemoryPressure(_ pressure: HostMemoryPressure) {
        self.hostMemoryPressure = pressure
        guard isEnabled, let _ = balloonDevice else { return }

        switch pressure {
        case .normal:
            // 宿主机内存充裕：恢复全量配置内存
            applyMemoryTarget(self.baseTargetMemoryBytes)
            self.statusDescription = "宿主机内存充裕 · 全量性能分配"
            self.savedMemoryMB = 0

        case .warning:
            // 宿主机内存偏高：通过 VirtIO Balloon 回垦 25% 物理内存还给 Mac
            let reduced = UInt64(Double(self.baseTargetMemoryBytes) * 0.75)
            let minAllowed: UInt64 = 2 * 1024 * 1024 * 1024 // 至少保留 2GB 确保 Linux 不发生 OOM
            let target = max(reduced, minAllowed)
            applyMemoryTarget(target)
            self.savedMemoryMB = Int((self.baseTargetMemoryBytes - target) / (1024 * 1024))
            self.statusDescription = "宿主机内存偏高 · 已回垦释放 \(savedMemoryMB) MB"

        case .critical:
            // 宿主机严重内存短缺：强力回垦 40% 物理内存还给 Mac
            let reduced = UInt64(Double(self.baseTargetMemoryBytes) * 0.60)
            let minAllowed: UInt64 = 2 * 1024 * 1024 * 1024
            let target = max(reduced, minAllowed)
            applyMemoryTarget(target)
            self.savedMemoryMB = Int((self.baseTargetMemoryBytes - target) / (1024 * 1024))
            self.statusDescription = "宿主机内存紧急 · 深度避让释放 \(savedMemoryMB) MB"
        }
    }

    private func applyMemoryTarget(_ targetBytes: UInt64) {
        guard let balloon = balloonDevice else { return }
        balloon.targetVirtualMachineMemorySize = targetBytes
        self.dynamicTargetMemoryGB = Double(targetBytes) / (1024 * 1024 * 1024)
    }
}
