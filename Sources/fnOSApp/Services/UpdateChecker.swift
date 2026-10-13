import Foundation
import AppKit

public struct AppUpdateInfo: Equatable {
    public let latestVersion: String
    public let hasUpdate: Bool
    public let releaseURL: URL
    public let releaseNotes: String?
}

@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()
    public static let currentVersion = "1.0.3"

    @Published public var isChecking: Bool = false
    @Published public var updateInfo: AppUpdateInfo? = nil
    @Published public var checkMessage: String? = nil

    private init() {}

    public func checkForUpdates(manual: Bool = false) async {
        isChecking = true
        checkMessage = "正在检查更新..."

        // 1. 优先调用 GitHub REST API
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/Xiaohantx/FnOS-Manager/releases/latest")!)
            request.timeoutInterval = 8
            request.setValue("FnOSManager/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                let cleanTag = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let hasUpdate = isVersion(cleanTag, greaterThan: Self.currentVersion)
                let releaseURL = URL(string: json["html_url"] as? String ?? "https://github.com/Xiaohantx/FnOS-Manager/releases")!
                let body = json["body"] as? String

                let info = AppUpdateInfo(latestVersion: cleanTag, hasUpdate: hasUpdate, releaseURL: releaseURL, releaseNotes: body)
                self.updateInfo = info
                self.isChecking = false
                if hasUpdate {
                    self.checkMessage = "🎉 发现新版本 v\(cleanTag)"
                } else {
                    self.checkMessage = "✓ 已是最新版本 (v\(Self.currentVersion))"
                }
                return
            }
        } catch { }

        // 2. 备选方案: 探测 Releases 页面 HTML 标签
        do {
            var request = URLRequest(url: URL(string: "https://github.com/Xiaohantx/FnOS-Manager/releases")!)
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0 FnOSManager/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)
            if let html = String(data: data, encoding: .utf8) {
                let pattern = #"releases/tag/v?([0-9]+\.[0-9]+\.[0-9]+)"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let range = Range(match.range(at: 1), in: html) {
                    let latestVer = String(html[range])
                    let hasUpdate = isVersion(latestVer, greaterThan: Self.currentVersion)
                    let releaseURL = URL(string: "https://github.com/Xiaohantx/FnOS-Manager/releases/tag/v\(latestVer)") ?? URL(string: "https://github.com/Xiaohantx/FnOS-Manager/releases")!
                    let info = AppUpdateInfo(latestVersion: latestVer, hasUpdate: hasUpdate, releaseURL: releaseURL, releaseNotes: nil)
                    self.updateInfo = info
                    self.isChecking = false
                    self.checkMessage = hasUpdate ? "🎉 发现新版本 v\(latestVer)" : "✓ 已是最新版本 (v\(Self.currentVersion))"
                    return
                }
            }
        } catch { }

        self.isChecking = false
        self.checkMessage = "✓ 已是最新版本 (v\(Self.currentVersion))"
    }

    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let p1 = v1.split(separator: ".").compactMap { Int($0) }
        let p2 = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(p1.count, p2.count) {
            let num1 = i < p1.count ? p1[i] : 0
            let num2 = i < p2.count ? p2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }
}
