import SwiftUI
import AppKit

public struct UnifiedISOCardView: View {
    @ObservedObject var isoFetcher: ISOFetcherService
    @ObservedObject var vmManager: VMManager
    let l10n: LocalizedStrings
    let onSelectCustomISO: () -> Void

    @State private var isDetailsExpanded: Bool = false
    @State private var isCheckingAnimation: Bool = false
    @State private var statusMessage: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if isDetailsExpanded {
                detailsBox
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isDetailsExpanded)
        .onAppear {
            if isoFetcher.fetchedISO == nil {
                isoFetcher.fetchedISO = ISOFetcherService.fallbackARMISO
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            // 左侧图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 18))
            }

            // 中间标题与就绪微标
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(l10n.smartISOCardTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(l10n.isoReadyBadge) (v1.2.0302)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.25), lineWidth: 0.5))
                }

                Text(l10n.smartISOCardSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.55))
            }

            Spacer()

            // 右侧动作区：详情折叠 + 检查更新
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation {
                        isDetailsExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(l10n.isoDetailsToggle)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: isDetailsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(Color.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: {
                    triggerCheckLatest()
                }) {
                    HStack(spacing: 5) {
                        if isoFetcher.isFetching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isoFetcher.isFetching ? l10n.fetchingInfo : (statusMessage ?? l10n.checkOfficialLatest))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [Color.blue, Color(red: 0.1, green: 0.45, blue: 0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detailsBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .background(Color.white.opacity(0.08))

            if let iso = isoFetcher.fetchedISO {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(l10n.md5Label + ":")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                            Text(iso.md5)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.3, green: 0.85, blue: 1.0))
                            Text(l10n.officialVerified)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(4)
                        }

                        Text("源地址: " + iso.url)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Button(action: {
                            isoFetcher.copyToClipboard(text: iso.md5, label: l10n.copyMD5Btn)
                        }) {
                            Text(l10n.copyMD5Btn)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            isoFetcher.copySignedURLToClipboard(rawURL: iso.url, label: l10n.copyLinkBtn)
                        }) {
                            Text(l10n.copyLinkBtn)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            onSelectCustomISO()
                        }) {
                            Text(l10n.customISOPick)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.cyan.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let toast = isoFetcher.copiedToast {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("\(toast) 成功！")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }

    private func triggerCheckLatest() {
        isoFetcher.fetchLatestISO { result in
            switch result {
            case .success:
                statusMessage = "已是最新版本"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    statusMessage = nil
                }
            case .failure:
                statusMessage = nil
            }
        }
    }
}
