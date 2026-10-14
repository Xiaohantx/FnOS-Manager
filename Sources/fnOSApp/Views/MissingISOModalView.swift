import SwiftUI

public struct MissingISOModalView: View {
    public var onCancel: () -> Void
    public var onConfirmDownload: () -> Void

    public var body: some View {
        ZStack {
            // 毛玻璃遮罩
            Color.black.opacity(0.45)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // 居中引导弹窗卡片
            VStack(spacing: 16) {
                // 引导图标徽章 (科技蓝光)
                ZStack {
                    Circle()
                        .fill(Color(red: 0.1, green: 0.55, blue: 1.0).opacity(0.15))
                        .frame(width: 52, height: 52)

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.65, blue: 1.0))
                }
                .padding(.top, 4)

                // 标题与说明
                VStack(spacing: 8) {
                    Text("获取飞牛私有云 (fnOS) 镜像")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("检测到尚未内置官方 ARM64 虚拟化安装镜像。点击「一键自动下载」将自动下载并校验官方镜像，完成后即可一键安装。")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)

                // 底部双操作按钮
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("稍后配置")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onConfirmDownload) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.to.line.compact")
                                .font(.system(size: 11, weight: .bold))
                            Text("一键获取镜像")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.15, green: 0.58, blue: 1.0), Color(red: 0.08, green: 0.44, blue: 0.92)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 330)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
