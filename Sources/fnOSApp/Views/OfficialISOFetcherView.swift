import SwiftUI
import AppKit

public struct OfficialISOFetcherView: View {
    @ObservedObject var isoFetcher: ISOFetcherService
    @ObservedObject var vmManager: VMManager
    let l10n: LocalizedStrings

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            if let iso = isoFetcher.fetchedISO {
                isoDetailsCard(iso: iso)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .onAppear {
            if isoFetcher.fetchedISO == nil {
                isoFetcher.fetchedISO = ISOFetcherService.fallbackARMISO
            }
        }
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    Text(l10n.fetchISOHeader)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("https://fnnas.com/download-arm")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.blue.opacity(0.8))
            }

            Spacer()

            Button(action: {
                isoFetcher.fetchLatestISO()
            }) {
                HStack(spacing: 5) {
                    if isoFetcher.isFetching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(l10n.fetchISOButton)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
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

    private func isoDetailsCard(iso: OfficialISOInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 镜像名称
            HStack(alignment: .top, spacing: 8) {
                Text(l10n.isoNameLabel + ":")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 85, alignment: .leading)
                Text(iso.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }

            // 直接下载链接
            HStack(alignment: .center, spacing: 8) {
                Text(l10n.directUrlLabel + ":")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 85, alignment: .leading)

                Text(iso.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)

                Spacer()

                Button(action: {
                    isoFetcher.copySignedURLToClipboard(rawURL: iso.url, label: l10n.copyLinkBtn)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text(l10n.copyLinkBtn)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: {
                    isoFetcher.openInBrowser(urlStr: iso.url)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 10))
                        Text(l10n.openInBrowserBtn)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.25))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            // MD5 校验和
            HStack(alignment: .center, spacing: 8) {
                Text(l10n.md5Label + ":")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 85, alignment: .leading)

                HStack(spacing: 8) {
                    Text(iso.md5)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.3, green: 0.85, blue: 1.0))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                        Text(l10n.officialVerified)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(5)
                }

                Spacer()

                Button(action: {
                    isoFetcher.copyToClipboard(text: iso.md5, label: l10n.copyMD5Btn)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text(l10n.copyMD5Btn)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            // 复制反馈
            if let toast = isoFetcher.copiedToast {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(toast) 成功！")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
                .padding(.top, 2)
            }

            // 本地已下载匹配检测
            localFileRow(iso: iso)
        }
        .padding(14)
        .background(Color.black.opacity(0.25))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func localFileRow(iso: OfficialISOInfo) -> some View {
        let candidatePaths = [
            "/Volumes/Han/下载/" + iso.fileName,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/" + iso.fileName).path
        ]
        let existingLocalPath = candidatePaths.first { FileManager.default.fileExists(atPath: $0) }

        return Group {
            if let localPath = existingLocalPath {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill.badge.plus")
                            .foregroundColor(.cyan)
                        Text(l10n.localFileFound + ": " + URL(fileURLWithPath: localPath).lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.8))
                    }

                    Spacer()

                    if vmManager.settings.isoPath != localPath {
                        Button(action: {
                            vmManager.settings.isoPath = localPath
                            vmManager.settings.save()
                        }) {
                            Text(l10n.useAsCurrentISO)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已设为当前启动镜像")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
    }
}
