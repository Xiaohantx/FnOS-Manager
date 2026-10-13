import Foundation

public final class HostsManager {
    public static let shared = HostsManager()

    private let hostsPath = "/etc/hosts"
    private let tagComment = "# fnOS Manager Local Domain"

    private init() {}

    /// 读取当前已配置的 .fnos 域名与 IP
    public func getCurrentDomainMapping() -> (domain: String, ip: String)? {
        guard let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return nil
        }
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: " ").map { String($0) }
            if parts.count >= 2 {
                let ip = parts[0]
                for domain in parts.dropFirst() {
                    if domain.hasSuffix(".fnos") {
                        return (domain, ip)
                    }
                }
            }
        }
        return nil
    }

    /// 根据当前 /etc/hosts 中配置的 .fnos IP，从 /var/db/dhcpd_leases 查找匹配的 MAC 地址，使虚拟机固定获得同一局域网 IP
    public func preferredMACForCurrentHosts() -> String? {
        guard let mapping = getCurrentDomainMapping() else { return nil }
        let targetIP = mapping.ip
        guard let leases = try? String(contentsOfFile: "/var/db/dhcpd_leases", encoding: .utf8) else {
            return nil
        }

        let blocks = leases.components(separatedBy: "}")
        for block in blocks {
            var blockIP: String?
            var blockMAC: String?
            for rawLine in block.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("ip_address=") {
                    blockIP = String(line.dropFirst("ip_address=".count))
                } else if line.hasPrefix("hw_address=") {
                    let val = String(line.dropFirst("hw_address=".count))
                    let macPart = val.components(separatedBy: ",").last ?? val
                    let normalized = macPart
                        .split(separator: ":")
                        .map { part in part.count == 1 ? "0\(part)" : String(part) }
                        .joined(separator: ":")
                    if normalized.split(separator: ":").count == 6 {
                        blockMAC = normalized.lowercased()
                    }
                }
            }
            if blockIP == targetIP, let mac = blockMAC {
                return mac
            }
        }
        return nil
    }

    /// 自动将 *.fnos 与自定义域名加入 macOS 系统代理忽略列表，防止开启 Clash/TUN 等系统代理时浏览器请求被代理拦截导致打不开
    public func ensureProxyBypass(domainPrefix: String = "nas") {
        let targetDomain = "\(domainPrefix).fnos"
        DispatchQueue.global(qos: .utility).async {
            let listProc = Process()
            listProc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            listProc.arguments = ["-listallnetworkservices"]
            let outPipe = Pipe()
            listProc.standardOutput = outPipe
            listProc.standardError = Pipe()
            guard (try? listProc.run()) != nil else { return }
            listProc.waitUntilExit()

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return }
            let services = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }

            for service in services {
                let getProc = Process()
                getProc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                getProc.arguments = ["-getproxybypassdomains", service]
                let getPipe = Pipe()
                getProc.standardOutput = getPipe
                getProc.standardError = Pipe()
                guard (try? getProc.run()) != nil else { continue }
                getProc.waitUntilExit()

                let getOut = String(data: getPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                var domains = getOut.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains("There aren't any") }

                var changed = false
                if !domains.contains("*.fnos") {
                    domains.append("*.fnos")
                    changed = true
                }
                if !domains.contains(targetDomain) {
                    domains.append(targetDomain)
                    changed = true
                }

                if changed {
                    let setProc = Process()
                    setProc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                    setProc.arguments = ["-setproxybypassdomains", service] + domains
                    setProc.standardOutput = Pipe()
                    setProc.standardError = Pipe()
                    try? setProc.run()
                    setProc.waitUntilExit()
                }
            }
        }
    }

    /// 更新或添加 hosts 映射记录 (例如: 192.168.64.2 nas.fnos)
    public func updateDomainMapping(prefix: String, targetIP: String, completion: @escaping (Result<Void, Error>) -> Void) {
        ensureProxyBypass(domainPrefix: prefix)
        let domain = "\(prefix).fnos"
        let entry = "\(targetIP) \(domain) \(tagComment)"
        
        let script = """
        do shell script "grep -v ' \(tagComment)' /etc/hosts > /tmp/hosts.fnos.tmp && echo '\(entry)' >> /tmp/hosts.fnos.tmp && mv /tmp/hosts.fnos.tmp /etc/hosts && dscacheutil -flushcache" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&errorInfo)
                if let error = errorInfo {
                    let errMsg = error[NSAppleScript.errorMessage] as? String ?? "未知授权错误"
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "HostsManager", code: -1, userInfo: [NSLocalizedDescriptionKey: errMsg])))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HostsManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法初始化 AppleScript"])))
                }
            }
        }
    }

    /// 移除 fnOS 相关的 hosts 映射
    public func removeDomainMapping(completion: @escaping (Result<Void, Error>) -> Void) {
        let script = """
        do shell script "grep -v ' \(tagComment)' /etc/hosts > /tmp/hosts.fnos.tmp && mv /tmp/hosts.fnos.tmp /etc/hosts && dscacheutil -flushcache" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&errorInfo)
                if let error = errorInfo {
                    let errMsg = error[NSAppleScript.errorMessage] as? String ?? "未知授权错误"
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "HostsManager", code: -1, userInfo: [NSLocalizedDescriptionKey: errMsg])))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HostsManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法初始化 AppleScript"])))
                }
            }
        }
    }
}
