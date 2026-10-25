import Foundation
import AppKit
import CryptoKit

public struct AppUpdateInfo: Equatable {
    public let latestVersion: String
    public let hasUpdate: Bool
    public let releaseURL: URL
    public let releaseNotes: String?
    public let downloadURL: URL?
    public let sha256: String?
}

@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()
    public static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    @Published public var isChecking: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var isInstalling: Bool = false
    @Published public var updateInfo: AppUpdateInfo? = nil
    @Published public var checkMessage: String? = nil
    @Published public var hasNewVersionBadge: Bool = false

    private let lastCheckKey = "last_update_check_timestamp"
    private let checkIntervalSeconds: TimeInterval = 12 * 3600

    private init() {
        if let lastUpdateVer = UserDefaults.standard.string(forKey: "cached_new_version"),
           isVersion(lastUpdateVer, greaterThan: Self.currentVersion) {
            self.hasNewVersionBadge = true
        }
    }

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
        guard !isChecking && !isDownloading && !isInstalling else { return }
        isChecking = true
        checkMessage = "正在检查更新..."
        updateInfo = nil

        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/Xiaohantx/FnOS-Manager/releases/latest")!)
            request.timeoutInterval = 15
            request.setValue("FnOSManager/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw NSError(domain: "FnOSManager.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "更新服务暂时不可用"])
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                throw NSError(domain: "FnOSManager.Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "更新信息格式无效"])
            }

            let cleanTag = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let hasUpdate = isVersion(cleanTag, greaterThan: Self.currentVersion)
            let releaseURL = URL(string: json["html_url"] as? String ?? "https://github.com/Xiaohantx/FnOS-Manager/releases")!
            let releaseNotes = json["body"] as? String
            let assetName = "FnOS-Manager-\(cleanTag)-arm64.dmg"
            let assets = json["assets"] as? [[String: Any]] ?? []
            let asset = assets.first { $0["name"] as? String == assetName }
            let downloadURL = (asset?["browser_download_url"] as? String).flatMap(URL.init(string:))
            let assetDigest = (asset?["digest"] as? String)?.replacingOccurrences(of: "sha256:", with: "").lowercased()
            let expectedDigest = (assetDigest?.count == 64 && assetDigest?.allSatisfy(\.isHexDigit) == true)
                ? assetDigest
                : extractChecksum(from: releaseNotes, assetName: assetName)

            updateInfo = AppUpdateInfo(
                latestVersion: cleanTag,
                hasUpdate: hasUpdate,
                releaseURL: releaseURL,
                releaseNotes: releaseNotes,
                downloadURL: downloadURL,
                sha256: expectedDigest
            )
            hasNewVersionBadge = hasUpdate
            if hasUpdate {
                UserDefaults.standard.set(cleanTag, forKey: "cached_new_version")
                if downloadURL != nil && expectedDigest != nil {
                    checkMessage = "发现新版本 v\(cleanTag)"
                } else {
                    checkMessage = "发现新版本，但安装包或校验信息暂不可用"
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "cached_new_version")
                checkMessage = "已是最新"
            }
        } catch {
            checkMessage = manual ? "检查更新失败：\(error.localizedDescription)" : "无法连接更新服务"
        }
        isChecking = false
    }

    public func downloadAndInstallUpdate() async {
        guard let info = updateInfo, info.hasUpdate else { return }
        guard let downloadURL = info.downloadURL,
              let expectedDigest = info.sha256,
              expectedDigest.count == 64,
              expectedDigest.allSatisfy(\.isHexDigit) else {
            checkMessage = "更新包缺少有效校验信息，已停止安装"
            return
        }
        guard !isChecking && !isDownloading && !isInstalling else { return }

        isDownloading = true
        checkMessage = "正在下载 v\(info.latestVersion)..."
        defer { isDownloading = false }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: downloadURL)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw NSError(domain: "FnOSManager.Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "下载更新包失败"])
            }

            let downloadedData = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
            let actualDigest = SHA256.hash(data: downloadedData).map { String(format: "%02x", Int($0)) }.joined()
            guard actualDigest.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
                throw NSError(domain: "FnOSManager.Update", code: 4, userInfo: [NSLocalizedDescriptionKey: "更新包校验失败，文件未安装"])
            }

            checkMessage = "校验通过，正在准备安装..."
            try prepareAndLaunchInstaller(dmgURL: temporaryURL, expectedVersion: info.latestVersion)
            isInstalling = true
            checkMessage = "安装程序已准备，应用即将重启..."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApp.terminate(nil)
            }
        } catch {
            isInstalling = false
            checkMessage = "更新失败：\(error.localizedDescription)"
        }
    }

    private func prepareAndLaunchInstaller(dmgURL: URL, expectedVersion: String) throws {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FnOSManagerUpdate-\(UUID().uuidString)", isDirectory: true)
        let mountPoint = workDirectory.appendingPathComponent("mounted", isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        do {
            _ = try runProcess("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, dmgURL.path])
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }

        do {
            let candidates = try fileManager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "app" }
            guard let sourceApp = candidates.first,
                  let downloadedBundle = Bundle(url: sourceApp),
                  downloadedBundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let bundledVersion = downloadedBundle.infoDictionary?["CFBundleShortVersionString"] as? String,
                  bundledVersion == expectedVersion else {
                throw NSError(domain: "FnOSManager.Update", code: 5, userInfo: [NSLocalizedDescriptionKey: "安装包中的应用身份或版本不匹配"])
            }

            let stagedApp = workDirectory.appendingPathComponent("FnOS Manager.app", isDirectory: true)
            try fileManager.copyItem(at: sourceApp, to: stagedApp)
            let helperURL = workDirectory.appendingPathComponent("install-update.sh")
            let appleScriptURL = workDirectory.appendingPathComponent("request-admin.applescript")
            try Self.updateHelperScript.write(to: helperURL, atomically: true, encoding: .utf8)
            try Self.adminAuthorizationScript.write(to: appleScriptURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            process.arguments = [
                "/bin/bash", helperURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                stagedApp.path,
                Bundle.main.bundleURL.standardizedFileURL.path,
                mountPoint.path,
                workDirectory.path,
                appleScriptURL.path
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            _ = try? runProcess("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }
    }

    private func runProcess(_ executablePath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "FnOSManager.Update", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "准备安装器失败" : text])
        }
        return text
    }

    private func extractChecksum(from releaseNotes: String?, assetName: String) -> String? {
        guard let releaseNotes else { return nil }
        let pattern = NSRegularExpression.escapedPattern(for: assetName) + ":\\s*([A-Fa-f0-9]{64})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: releaseNotes, range: NSRange(releaseNotes.startIndex..., in: releaseNotes)),
              let range = Range(match.range(at: 1), in: releaseNotes) else { return nil }
        return String(releaseNotes[range]).lowercased()
    }

    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let p1 = v1.split(separator: ".").compactMap { Int($0) }
        let p2 = v2.split(separator: ".").compactMap { Int($0) }
        guard !p1.isEmpty else { return false }
        for i in 0..<max(p1.count, p2.count) {
            let num1 = i < p1.count ? p1[i] : 0
            let num2 = i < p2.count ? p2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }

    private static let adminAuthorizationScript = #"""
on run argv
    set helperPath to item 1 of argv
    set stagedApp to item 2 of argv
    set destinationApp to item 3 of argv
    set backupApp to item 4 of argv
    set command to quoted form of helperPath & " --elevated " & quoted form of stagedApp & " " & quoted form of destinationApp & " " & quoted form of backupApp
    do shell script command with administrator privileges
end run
"""#

    private static let updateHelperScript = #"""
#!/bin/bash
set -euo pipefail

replace_app() {
    staged_app="$1"
    destination_app="$2"
    backup_app="$3"
    replacement_app="$destination_app.new.$$"
    /usr/bin/ditto "$staged_app" "$replacement_app"
    if [ -e "$destination_app" ]; then
        /bin/mv "$destination_app" "$backup_app"
    fi
    if /bin/mv "$replacement_app" "$destination_app"; then
        /bin/rm -rf "$backup_app"
    else
        if [ -e "$backup_app" ]; then /bin/mv "$backup_app" "$destination_app"; fi
        exit 1
    fi
}

if [ "$1" = "--elevated" ]; then
    replace_app "$2" "$3" "$4"
    exit 0
fi

app_pid="$1"
staged_app="$2"
destination_app="$3"
mount_point="$4"
work_directory="$5"
apple_script="$6"

for ((attempt = 0; attempt < 120; attempt++)); do
    if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
    sleep 1
done
if kill -0 "$app_pid" 2>/dev/null; then exit 1; fi

backup_app="$destination_app.backup.$$"
parent_directory="$(/usr/bin/dirname "$destination_app")"
if [ -w "$parent_directory" ]; then
    replace_app "$staged_app" "$destination_app" "$backup_app"
else
    if ! /usr/bin/osascript "$apple_script" "$0" "$staged_app" "$destination_app" "$backup_app"; then
        /usr/bin/hdiutil detach "$mount_point" -quiet || true
        /usr/bin/open -na "$destination_app" || true
        exit 1
    fi
fi

/usr/bin/hdiutil detach "$mount_point" -quiet || true
/bin/rm -rf "$work_directory"
/usr/bin/open -na "$destination_app"
"""#
}
