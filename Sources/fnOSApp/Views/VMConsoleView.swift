import SwiftUI
import Virtualization
import AppKit

public struct VMConsoleView: NSViewRepresentable {
    public let virtualMachine: VZVirtualMachine?

    public init(virtualMachine: VZVirtualMachine?) {
        self.virtualMachine = virtualMachine
    }

    public func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.virtualMachine = virtualMachine
        view.capturesSystemKeys = true
        return view
    }

    public func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        if nsView.virtualMachine !== virtualMachine {
            nsView.virtualMachine = virtualMachine
        }
    }

    public static func dismantleNSView(_ nsView: VZVirtualMachineView, coordinator: ()) {
        nsView.virtualMachine = nil
    }
}

public struct VMConsoleContainerView: View {
    @ObservedObject var vmManager: VMManager

    public var body: some View {
        VStack(spacing: 0) {
            if let vm = vmManager.vzVirtualMachine, vmManager.status.isRunningOrStarting {
                VMConsoleView(virtualMachine: vm)
                    .frame(minWidth: 700, minHeight: 460)
            } else if vmManager.status.isRunningOrStarting {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在加载虚拟机硬件与显示输出...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "display")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("虚拟机未运行")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("点击顶部「启动 fnOS」即可开启系统运行。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }

            // Bottom bar with installation quick-action
            if vmManager.status == .installing {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("首次安装模式中：请在上方窗口内跟随飞牛安装向导选择磁盘完成安装。")
                        .font(.caption)
                    Spacer()
                    Button("完成安装并重启进入日常模式") {
                        vmManager.markInstalledAndRestart()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
}
