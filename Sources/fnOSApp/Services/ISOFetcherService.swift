import Foundation
import CryptoKit
import AppKit

public struct OfficialISOInfo: Equatable, Codable {
    public var name: String
    public var url: String
    public var md5: String
    public var thunder: String?
    public var fileName: String

    public init(name: String, url: String, md5: String, thunder: String? = nil, fileName: String? = nil) {
        self.name = name
        self.url = url
        self.md5 = md5
        self.thunder = thunder
        self.fileName = fileName ?? (URL(string: url)?.lastPathComponent ?? "fnos_arm.iso")
    }
}

public class ISOFetcherService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = ISOFetcherService()

    @Published public var isFetching: Bool = false
    @Published public var fetchedISO: OfficialISOInfo? = nil
    @Published public var errorMessage: String? = nil
    @Published public var copiedToast: String? = nil

    // 内置镜像状态管理
    @Published public var hasBuiltInISO: Bool = false
    @Published public var localISOMD5: String? = nil
    @Published public var hasUpdateAvailable: Bool = false
    @Published public var checkStatusMessage: String? = nil

    // 应用内下载进度追踪
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadedSizeStr: String = ""
    @Published public var totalSizeStr: String = ""
    @Published public var downloadSpeedStr: String = ""
    @Published public var downloadSuccess: Bool = false
    @Published public var localFilePath: String? = nil

    public var builtInISOPath: String {
        VMSettings.defaultVMDataDir + "/fnos_arm64.iso"
    }

    public var builtInISOMD5Path: String {
        VMSettings.defaultVMDataDir + "/fnos_arm64.iso.md5"
    }

    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private var downloadStartTime: Date?
    private var lastBytesWritten: Int64 = 0
    private var lastUIUpdateTime: TimeInterval = 0
    private var onFinishedCallback: ((String) -> Void)?

    // 官方页面已验证基准 Fallback (确保离线或解析异常时 100% 可用)
    public static let fallbackARMISO = OfficialISOInfo(
        name: "UEFI ARM 安装镜像 ISO (支持 此芯 P1 / 苹果M系列（虚拟化) ）等",
        url: "https://iso.liveupdate.fnnas.com/arm/iso/armsr/fnos_Mainland-PE_arm_1.2.0302_armsr_2301.iso",
        md5: "7babaa1bf2405a6880e802904b58a809",
        thunder: "thunder://QUFodHRwOi8vdGh1bmRlci5saXZldXBkYXRlLmZubmFzLmNvbTo4MDgwL2FybS9pc28vYXJtc3IvZm5vc19NYWlubGFuZC1QRV9hcm1fMS4yLjAzMDJfYXJtc3JfMjMwMS5pc29aWg==",
        fileName: "fnos_Mainland-PE_arm_1.2.0302_armsr_2301.iso"
    )

    public override init() {
        super.init()
        self.fetchedISO = Self.fallbackARMISO
        refreshBuiltInISOState()
    }

    /// 检测内置目录下是否已包含镜像，并比对本地与远端 MD5
    public func refreshBuiltInISOState() {
        let fm = FileManager.default
        if fm.fileExists(atPath: builtInISOPath),
           let attrs = try? fm.attributesOfItem(atPath: builtInISOPath),
           let fileSize = attrs[.size] as? UInt64,
           fileSize > 1_000_000 {
            self.hasBuiltInISO = true
            self.localFilePath = builtInISOPath

            if let savedMD5 = try? String(contentsOfFile: builtInISOMD5Path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !savedMD5.isEmpty {
                self.localISOMD5 = savedMD5.lowercased()
                self.updateComparisonState()
            } else {
                computeFileMD5Async(path: builtInISOPath) { [weak self] computed in
                    guard let self = self, let computed = computed else { return }
                    self.localISOMD5 = computed.lowercased()
                    try? computed.lowercased().write(toFile: self.builtInISOMD5Path, atomically: true, encoding: .utf8)
                    self.updateComparisonState()
                }
            }
        } else {
            self.hasBuiltInISO = false
            self.localISOMD5 = nil
            self.hasUpdateAvailable = false
            self.localFilePath = nil
        }
    }

    private func updateComparisonState() {
        guard hasBuiltInISO,
              let localMD5 = localISOMD5?.lowercased(),
              let remoteMD5 = fetchedISO?.md5.lowercased() else {
            hasUpdateAvailable = false
            return
        }
        hasUpdateAvailable = (localMD5 != remoteMD5)
    }

    /// 流式计算大文件 MD5（后台线程执行，不阻塞 UI）
    private func computeFileMD5Async(path: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let handle = FileHandle(forReadingAtPath: path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            defer { try? handle.close() }

            var hasher = Insecure.MD5()
            let chunkSize = 4 * 1024 * 1024
            while autoreleasepool(invoking: {
                guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else {
                    return false
                }
                hasher.update(data: data)
                return true
            }) {}

            let digest = hasher.finalize()
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            DispatchQueue.main.async {
                completion(hex)
            }
        }
    }

    /// 检查官方最新镜像并与本地内置镜像比对 MD5
    public func checkRemoteUpdate() {
        checkStatusMessage = nil
        errorMessage = nil
        fetchLatestISO { [weak self] _ in
            guard let self = self else { return }
            self.refreshBuiltInISOState()
            if self.hasBuiltInISO && !self.hasUpdateAvailable {
                self.checkStatusMessage = "已是最新"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self.checkStatusMessage == "已是最新" {
                        self.checkStatusMessage = nil
                    }
                }
            }
        }
    }

    /// 一键获取或更新官方镜像到内置目录（先换取 download-sign 签名再下载）
    public func downloadBuiltInISO(onFinished: ((String) -> Void)? = nil) {
        guard !isDownloading else { return }
        errorMessage = nil
        checkStatusMessage = nil
        isDownloading = true
        downloadProgress = 0.0
        downloadedSizeStr = "0.00 GB"
        totalSizeStr = "3.16 GB"
        downloadSpeedStr = " 0.0 MB/s"
        downloadSuccess = false
        downloadStartTime = Date()
        lastUIUpdateTime = 0
        onFinishedCallback = onFinished

        fetchLatestISO { [weak self] _ in
            guard let self = self else { return }
            let targetISO = self.fetchedISO ?? Self.fallbackARMISO
            self.fetchSignedDownloadURL(rawURL: targetISO.url) { [weak self] signedURL in
                guard let self = self, let url = URL(string: signedURL) else {
                    self?.isDownloading = false
                    self?.errorMessage = "获取下载签名失败"
                    return
                }
                self.downloadStartTime = Date()
                self.downloadTask = self.urlSession.downloadTask(with: url)
                self.downloadTask?.resume()
            }
        }
    }

    /// 清理已内置的镜像文件，释放空间
    public func clearBuiltInISO() {
        if isDownloading {
            cancelDownload()
        }
        let fm = FileManager.default
        try? fm.removeItem(atPath: builtInISOPath)
        try? fm.removeItem(atPath: builtInISOMD5Path)
        hasBuiltInISO = false
        localISOMD5 = nil
        hasUpdateAvailable = false
        localFilePath = nil
        checkStatusMessage = nil
        errorMessage = nil
    }

    /// 从 https://fnnas.com/download-arm 动态提取最新镜像与 MD5
    public func fetchLatestISO(completion: ((Result<OfficialISOInfo, Error>) -> Void)? = nil) {
        isFetching = true
        errorMessage = nil

        guard let pageURL = URL(string: "https://fnnas.com/download-arm") else {
            let fallback = Self.fallbackARMISO
            self.fetchedISO = fallback
            self.isFetching = false
            self.updateComparisonState()
            completion?(.success(fallback))
            return
        }

        var request = URLRequest(url: pageURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false

                guard let data = data, let html = String(data: data, encoding: .utf8) else {
                    let fallback = Self.fallbackARMISO
                    self.fetchedISO = fallback
                    self.updateComparisonState()
                    completion?(.success(fallback))
                    return
                }

                if let parsed = self.parseISOFromHTML(html) {
                    self.fetchedISO = parsed
                    self.updateComparisonState()
                    completion?(.success(parsed))
                } else {
                    let fallback = Self.fallbackARMISO
                    self.fetchedISO = fallback
                    self.updateComparisonState()
                    completion?(.success(fallback))
                }
            }
        }.resume()
    }

    private func parseISOFromHTML(_ html: String) -> OfficialISOInfo? {
        let urlPattern = #"https://iso\.liveupdate\.fnnas\.com/arm/iso/armsr/[a-zA-Z0-9_\-\.]+\.iso"#
        guard let urlRegex = try? NSRegularExpression(pattern: urlPattern),
              let urlMatch = urlRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let urlRange = Range(urlMatch.range, in: html) else {
            return nil
        }
        let urlStr = String(html[urlRange])

        let snippetStart = max(html.startIndex, html.index(urlRange.lowerBound, offsetBy: -300, limitedBy: html.startIndex) ?? html.startIndex)
        let snippetEnd = min(html.endIndex, html.index(urlRange.upperBound, offsetBy: 300, limitedBy: html.endIndex) ?? html.endIndex)
        let snippet = String(html[snippetStart..<snippetEnd])

        var md5Str = "7babaa1bf2405a6880e802904b58a809"
        let hashPattern = #"hash["\\]*:\s*["\\]*([a-fA-F0-9]{32})"#
        if let hashRegex = try? NSRegularExpression(pattern: hashPattern),
           let hashMatch = hashRegex.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
           let hashRange = Range(hashMatch.range(at: 1), in: snippet) {
            md5Str = String(snippet[hashRange])
        }

        var thunderStr: String? = nil
        let thunderPattern = #"thunder["\\]*:\s*["\\]*(thunder://[a-zA-Z0-9=+/]+)"#
        if let thunderRegex = try? NSRegularExpression(pattern: thunderPattern),
           let thunderMatch = thunderRegex.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
           let thunderRange = Range(thunderMatch.range(at: 1), in: snippet) {
            thunderStr = String(snippet[thunderRange])
        }

        return OfficialISOInfo(
            name: "UEFI ARM 安装镜像 ISO (支持 此芯 P1 / 苹果M系列（虚拟化) ）等",
            url: urlStr,
            md5: md5Str,
            thunder: thunderStr,
            fileName: URL(string: urlStr)?.lastPathComponent ?? "fnos_arm.iso"
        )
    }

    /// 调用飞牛官方签名接口 POST https://fnnas.com/asset/download-sign 换取带 ?sign=...&t=... 的防 403 下载直链
    public func fetchSignedDownloadURL(rawURL: String, completion: @escaping (String) -> Void) {
        let baseRawURL = rawURL.components(separatedBy: "?").first ?? rawURL
        guard let signAPI = URL(string: "https://fnnas.com/asset/download-sign") else {
            completion(rawURL)
            return
        }

        var request = URLRequest(url: signAPI)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://fnnas.com/download-arm", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": baseRawURL])

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let signedURL = json["url"] as? String,
                   !signedURL.isEmpty {
                    completion(signedURL)
                } else {
                    completion(rawURL)
                }
            }
        }.resume()
    }

    public func copyToClipboard(text: String, label: String = "已复制到剪贴板") {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        self.copiedToast = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.copiedToast == label {
                self.copiedToast = nil
            }
        }
    }

    public func copySignedURLToClipboard(rawURL: String, label: String = "已复制签名直链") {
        self.copiedToast = "正在获取签名…"
        fetchSignedDownloadURL(rawURL: rawURL) { [weak self] signedURL in
            self?.copyToClipboard(text: signedURL, label: label)
        }
    }

    public func openInBrowser(urlStr: String) {
        self.copiedToast = "正在换取签名…"
        fetchSignedDownloadURL(rawURL: urlStr) { [weak self] signedURL in
            if let url = URL(string: signedURL) {
                NSWorkspace.shared.open(url)
                self?.copiedToast = "已拉起签名下载"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self?.copiedToast == "已拉起签名下载" {
                        self?.copiedToast = nil
                    }
                }
            }
        }
    }

    public func startDownload(iso: OfficialISOInfo, onFinished: @escaping (String) -> Void) {
        downloadBuiltInISO(onFinished: onFinished)
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
    }

    // MARK: - URLSessionDownloadDelegate
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            guard totalBytesExpectedToWrite > 0 else { return }
            let now = Date().timeIntervalSinceReferenceDate
            let isComplete = (totalBytesWritten >= totalBytesExpectedToWrite)
            // 节流：每 0.25 秒最多刷新一次 UI，避免高频刷新导致闪烁
            guard isComplete || (now - self.lastUIUpdateTime >= 0.25) else { return }
            self.lastUIUpdateTime = now

            self.downloadProgress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))

            // 固定字数格式：始终以 GB 为单位并保留 2 位小数 (如 "0.08 GB", "1.20 GB", "3.16 GB")，严格固定 7 字符
            let downGB = min(9.99, max(0.0, Double(totalBytesWritten) / 1_000_000_000.0))
            let totalGB = min(9.99, max(0.01, Double(totalBytesExpectedToWrite) / 1_000_000_000.0))
            self.downloadedSizeStr = String(format: "%04.2f GB", downGB)
            self.totalSizeStr = String(format: "%04.2f GB", totalGB)

            if let startTime = self.downloadStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0.2 {
                    let speedMBps = (Double(totalBytesWritten) / elapsed) / 1_000_000.0
                    let clampedSpeed = min(999.9, max(0.0, speedMBps))
                    // 固定字数格式：始终保留 1 位小数，不足 10 MB/s 时补等宽空格 (如 " 8.5 MB/s", "72.0 MB/s")
                    self.downloadSpeedStr = String(format: "%4.1f MB/s", clampedSpeed)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let targetDirURL = URL(fileURLWithPath: VMSettings.defaultVMDataDir)
        let destinationURL = URL(fileURLWithPath: builtInISOPath)
        let expectedMD5 = (self.fetchedISO?.md5 ?? Self.fallbackARMISO.md5).lowercased()

        do {
            try FileManager.default.createDirectory(at: targetDirURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            try? expectedMD5.write(toFile: self.builtInISOMD5Path, atomically: true, encoding: .utf8)

            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadSuccess = true
                self.localFilePath = destinationURL.path
                self.localISOMD5 = expectedMD5
                self.hasBuiltInISO = true
                self.hasUpdateAvailable = false
                self.onFinishedCallback?(destinationURL.path)
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.errorMessage = "内置镜像保存失败: \(error.localizedDescription)"
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if let error = error as NSError?, error.code != NSURLErrorCancelled {
                self.isDownloading = false
                self.errorMessage = "获取镜像中断: \(error.localizedDescription)"
            }
        }
    }
}
