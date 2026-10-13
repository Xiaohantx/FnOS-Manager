import SwiftUI
import WebKit
import AppKit

public struct WebViewWrapper: NSViewRepresentable {
    let url: URL
    let reloadTrigger: UUID

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

public struct WebDashboardView: View {
    @ObservedObject var vmManager: VMManager
    @State private var reloadID = UUID()

    private var targetURL: URL? {
        if let ip = vmManager.currentIP {
            return URL(string: "http://\(ip):\(vmManager.settings.webPort)")
        }
        return nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Actions Bar
            HStack(spacing: 12) {
                if let url = targetURL {
                    HStack {
                        Image(systemName: "lock.open.trianglebadge.exclamationmark")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)

                    Button(action: { reloadID = UUID() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新页面")

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("复制网址")

                    Button(action: {
                        NSWorkspace.shared.open(url)
                    }) {
                        Label("在浏览器中打开", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Web 服务未连接")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Circle()
                    .fill(vmManager.isWebUIAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(vmManager.isWebUIAvailable ? "服务在线" : "正在等待端口 \(vmManager.settings.webPort)...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main View Area
            if let url = targetURL, vmManager.isWebUIAvailable {
                WebViewWrapper(url: url, reloadTrigger: reloadID)
                    .id(reloadID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    if vmManager.status == .stopped {
                        Image(systemName: "server.rack")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("飞牛 OS 尚未运行")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("请点击顶部或控制中心的「运行」按钮启动系统。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if vmManager.status == .installing {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("系统正在安装中")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("请切换到「虚拟机屏幕」标签页，跟随安装向导完成系统安装与初始化。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("正在等待飞牛 Web 管理服务响应...")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text(vmManager.currentIP != nil
                             ? "检测到虚拟机 IP: \(vmManager.currentIP!)，正在等待端口 \(vmManager.settings.webPort) 启动..."
                             : "正在通过 DHCP 侦测虚拟机网络地址，请稍候（通常需要 20~40 秒）...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
}
