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
    public static let currentVersion = "1.0.4"

    @Published public var isChecking: Bool = false
    @Published public var updateInfo: AppUpdateInfo? = nil
    @Published public var checkMessage: String? = nil
    @Published public var hasNewVersionBadge: Bool = false

    private let lastCheckKey = "last_update_check_timestamp"
    private let checkIntervalSeconds: TimeInterval = 12 * 3600 // 12 小时检查一次防限流

    private init() {
        // 读取本地历史更新状态
        if let lastUpdateVer = UserDefaults.standard.string(forKey: "cached_new_version"),
           isVersion(lastUpdateVer, greaterThan: Self.currentVersion) {
            self.hasNewVersionBadge = true
        }
    }

    /// 应用启动时在后台静默检查更新 (带 12 小时节流，防止触发 GitHub API 限流)
    public func checkInBackgroundOnLaunch() {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - lastCheck < checkIntervalSeconds && hasNewVersionBadge {
            return
        }

        Task {
            await checkForUpdates(manual: false)
            UserDefaults.standard.set(now, forKey: lastCheckKey)
        }
    }

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
                self.hasNewVersionBadge = hasUpdate
                if hasUpdate {
                    UserDefaults.standard.set(cleanTag, forKey: "cached_new_version")
                    self.checkMessage = "发现新版本 v\(cleanTag)"
                } else {
                    UserDefaults.standard.removeObject(forKey: "cached_new_version")
                    self.checkMessage = "已是最新版本"
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
                    self.hasNewVersionBadge = hasUpdate
                    if hasUpdate {
                        UserDefaults.standard.set(latestVer, forKey: "cached_new_version")
                        self.checkMessage = "发现新版本 v\(latestVer)"
                    } else {
                        UserDefaults.standard.removeObject(forKey: "cached_new_version")
                        self.checkMessage = "已是最新版本"
                    }
                    return
                }
            }
        } catch { }

        self.isChecking = false
        self.checkMessage = "已是最新版本"
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
