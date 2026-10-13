import SwiftUI
import AppKit

public struct HardwarePresetCardView: View {
    @ObservedObject var vmManager: VMManager
    @ObservedObject var perfEngine = VMPerformanceEngine.shared
    let l10n: LocalizedStrings

    @State private var isCustomExpanded: Bool = false

    private var currentPreset: String {
        let cpu = vmManager.settings.cpuCount
        let mem = vmManager.settings.memorySizeGB
        if cpu == 2 && mem == 4 {
            return "light"
        } else if cpu == 4 && mem == 8 {
            return "balanced"
        } else if cpu >= 6 && mem >= 16 {
            return "power"
        }
        return "custom"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            // 三档场景预设单选卡片
            HStack(spacing: 10) {
                presetCard(
                    id: "light",
                    title: l10n.presetLightTitle,
                    desc: l10n.presetLightDesc,
                    isSelected: currentPreset == "light",
                    isRecommended: false
                ) {
                    applyPreset(cpu: 2, mem: 4)
                }

                presetCard(
                    id: "balanced",
                    title: l10n.presetBalancedTitle,
                    desc: l10n.presetBalancedDesc,
                    isSelected: currentPreset == "balanced",
                    isRecommended: true
                ) {
                    applyPreset(cpu: 4, mem: 8)
                }

                presetCard(
                    id: "power",
                    title: l10n.presetPowerTitle,
                    desc: l10n.presetPowerDesc,
                    isSelected: currentPreset == "power",
                    isRecommended: false
                ) {
                    let maxCpu = min(6, ProcessInfo.processInfo.activeProcessorCount)
                    applyPreset(cpu: max(maxCpu, 4), mem: 16)
                }
            }

            // 存储说明与高级微调入口
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 11))
                    Text(l10n.sparseDiskHint)
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.6))
                }

                Spacer()

                Button(action: {
                    withAnimation {
                        isCustomExpanded.toggle()
                    }
                }) {
                    Text(l10n.advancedCustomToggle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)

            // 动态性能调优指示条 (VirtIO 动态伸缩 & 宿主机无感避让)
            HStack(spacing: 6) {
                Image(systemName: "bolt.badge.automatic.fill")
                    .foregroundColor(perfEngine.isBallooningActive ? .green : .cyan)
                    .font(.system(size: 11))

                Text(perfEngine.isBallooningActive ? perfEngine.statusDescription : l10n.dynamicOptimizationHint)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.65))

                Spacer()

                if perfEngine.savedMemoryMB > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text("已节省 \(perfEngine.savedMemoryMB) MB")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(4)
                }
            }
            .padding(.top, 1)

            // 折叠的高级自定义微调区
            if isCustomExpanded {
                advancedCustomBox
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCustomExpanded)
    }

    private var headerRow: some View {
        HStack {
            HStack(spacing: 6) {
                Text(l10n.hardwarePresetSection)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(l10n.hardwareAdaptiveMac)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            Spacer()

            Text(l10n.presetZeroMathHint)
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.45))
        }
    }

    private func presetCard(
        id: String,
        title: String,
        desc: String,
        isSelected: Bool,
        isRecommended: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))

                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? Color.blue.opacity(0.9) : Color.white.opacity(0.45))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                )

                if isRecommended {
                    Text(l10n.presetBalancedTag)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var advancedCustomBox: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(l10n.cpuCoresLabel): \(vmManager.settings.cpuCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
                Stepper("", value: $vmManager.settings.cpuCount, in: 2...8)
                    .labelsHidden()
                    .onChange(of: vmManager.settings.cpuCount) { _, _ in vmManager.settings.save() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(l10n.memoryLabel): \(vmManager.settings.memorySizeGB) GB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
                Stepper("", value: $vmManager.settings.memorySizeGB, in: 4...16, step: 2)
                    .labelsHidden()
                    .onChange(of: vmManager.settings.memorySizeGB) { _, _ in vmManager.settings.save() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(l10n.dataDiskSizeLabel): \(vmManager.settings.dataDiskSizeGB) GB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
                Picker("", selection: $vmManager.settings.dataDiskSizeGB) {
                    Text("128 GB").tag(128)
                    Text("256 GB").tag(256)
                    Text("512 GB").tag(512)
                    Text("1024 GB (1TB)").tag(1024)
                }
                .labelsHidden()
                .onChange(of: vmManager.settings.dataDiskSizeGB) { _, _ in vmManager.settings.save() }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.25))
        .cornerRadius(10)
        .padding(.top, 4)
    }

    private func applyPreset(cpu: Int, mem: Int) {
        vmManager.settings.cpuCount = cpu
        vmManager.settings.memorySizeGB = mem
        vmManager.settings.save()
    }
}
