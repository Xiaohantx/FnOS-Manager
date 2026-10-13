import SwiftUI

public struct ResetConfirmModalView: View {
    public var onCancel: () -> Void
    public var onConfirm: () -> Void

    public var body: some View {
        ZStack {
            // 毛玻璃遮罩
            Color.black.opacity(0.45)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // 居中弹窗卡片
            VStack(spacing: 16) {
                // 警示图标徽章
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.15))
                        .frame(width: 52, height: 52)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.04))
                }
                .padding(.top, 4)

                // 标题与说明
                VStack(spacing: 8) {
                    Text("确定要重置 fnOS 虚拟机吗？")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("重置操作将强制重启底层虚拟化内核。未落盘的缓存数据可能会丢失，系统将在约 15 秒后重新就绪。")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)

                // 底部双操作按钮
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("取消")
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

                    Button(action: onConfirm) {
                        Text("确认重置")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.95, green: 0.25, blue: 0.22), Color(red: 0.82, green: 0.16, blue: 0.15)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .shadow(color: Color.red.opacity(0.35), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
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
