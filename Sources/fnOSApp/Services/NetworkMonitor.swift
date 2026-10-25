import Foundation
import Network
import Virtualization
import Darwin

public class NetworkMonitor {
    public static let shared = NetworkMonitor()

    private struct AdditionalForwarder {
        let listenFD: Int32
        let targetHost: String
        let bindHost: String
        let generation: UInt64
    }

    private var timer: Timer?
    private var isSearching = false
    private var lanAccessEnabled = false
    private var configuredForwardingPorts: [Int] = [3000]

    private init() {}

    /// The host Mac's LAN address, used for links that other devices can reach.
    public var localLANIPAddress: String? {
        let addresses = hostIPv4AddressesByInterface()
        if let interface = defaultRouteInterface(), interface.hasPrefix("en"),
           let address = addresses[interface] {
            return address
        }
        if let address = addresses["en0"] {
            return address
        }
        return addresses.sorted { $0.key < $1.key }.first?.value
    }

    private func hostIPv4AddressesByInterface() -> [String: String] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [:] }
        defer { freeifaddrs(ifap) }

        var addresses: [String: String] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let socketAddress = interface.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.pointee.ifa_name)
            guard name.hasPrefix("en"), Int32(interface.pointee.ifa_flags) & IFF_UP != 0 else { continue }

            var rawAddress = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var addressBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let converted = addressBuffer.withUnsafeMutableBufferPointer { buffer in
                inet_ntop(AF_INET, &rawAddress, buffer.baseAddress, socklen_t(buffer.count))
            }
            guard converted != nil else { continue }

            let address = String(cString: addressBuffer)
            guard !address.hasPrefix("127."), !address.hasPrefix("169.254."), address != "0.0.0.0" else { continue }
            addresses[name] = address
        }
        return addresses
    }

    private func defaultRouteInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8),
                  let line = text.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") }) else {
                return nil
            }
            return line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
        } catch {
            return nil
        }
    }

    public func startMonitoring(targetMAC: VZMACAddress, targetPort: Int = 5666, onFound: @escaping (String) -> Void, onPortOpen: @escaping (Bool) -> Void) {
        stopMonitoring()

        let macStr = targetMAC.string.lowercased()
        var knownIP: String? = nil
        var failedChecks = 0

        // Poll every 3 seconds (lightweight backoff when stable)
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isSearching else { return }
            self.isSearching = true

            DispatchQueue.global(qos: .utility).async {
                // 严格通过 ARP 表或系统 DHCP 租约匹配真实虚拟机 MAC，杜绝代理软件造成假阳性 IP
                var detectedIP: String? = self.findIPFromARP(matchingMAC: macStr)
                    ?? self.findIPFromDHCPLeases(matchingMAC: macStr)
                    ?? knownIP

                if let ip = detectedIP {
                    knownIP = ip
                    DispatchQueue.main.async {
                        onFound(ip)
                    }
                    var candidatePorts = [targetPort, 5666, 80]
                    candidatePorts.append(contentsOf: self.configuredPortsSnapshot())
                    var checkedPorts = Set<Int>()
                    let isOpen = candidatePorts.contains { port in
                        guard checkedPorts.insert(port).inserted else { return false }
                        return self.checkTCPPortDirect(host: ip, port: port, timeout: 0.6)
                    }
                    if isOpen {
                        failedChecks = 0
                    } else {
                        failedChecks += 1
                        if failedChecks >= 3 {
                            knownIP = nil
                            detectedIP = nil
                        }
                    }
                    DispatchQueue.main.async {
                        onPortOpen(isOpen)
                    }
                } else {
                    DispatchQueue.main.async {
                        onPortOpen(false)
                    }
                }

                self.isSearching = false
            }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isSearching = false
        stopLocalForwarder()
    }

    public func setLANAccessEnabled(_ enabled: Bool) {
        forwarderLock.lock()
        guard lanAccessEnabled != enabled else {
            forwarderLock.unlock()
            return
        }
        lanAccessEnabled = enabled
        let targetHost = forwardedTargetHost
        let targetPort = forwardedPort
        let additionalPorts = configuredForwardingPorts
        forwarderLock.unlock()

        if !targetHost.isEmpty, targetPort > 0 {
            ensureLocalForwarder(targetHost: targetHost, port: targetPort)
            ensureAdditionalForwarders(targetHost: targetHost, consolePort: targetPort, ports: additionalPorts)
        }
    }

    public func setAdditionalForwardingPorts(_ ports: [Int]) {
        let normalizedPorts = Array(Set(ports.filter { (1...65535).contains($0) })).sorted()
        forwarderLock.lock()
        configuredForwardingPorts = normalizedPorts
        let targetHost = forwardedTargetHost
        let consolePort = forwardedPort
        forwarderLock.unlock()

        if !targetHost.isEmpty, consolePort > 0 {
            ensureAdditionalForwarders(targetHost: targetHost, consolePort: consolePort, ports: normalizedPorts)
        }
    }

    private func findIPFromARP(matchingMAC: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-an"]

        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let normalizedTarget = normalizeMAC(matchingMAC)
                for line in output.components(separatedBy: .newlines) {
                    guard !line.contains("(incomplete)") else { continue }
                    // Line format: ? (192.168.64.2) at 52:54:0:xx:yy:zz on bridge100 ...
                    let parts = line.components(separatedBy: " ")
                    if parts.count >= 4,
                       let ipPart = parts.first(where: { $0.hasPrefix("(") && $0.hasSuffix(")") }),
                       let atIndex = parts.firstIndex(of: "at"),
                       atIndex + 1 < parts.count {
                        let macPart = parts[atIndex + 1]
                        if normalizeMAC(macPart) == normalizedTarget {
                            return ipPart.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                        }
                    }
                }
            }
        } catch {
            // Ignore ARP failure
        }
        return nil
    }

    private func findIPFromDHCPLeases(matchingMAC: String) -> String? {
        guard let content = try? String(contentsOfFile: "/var/db/dhcpd_leases", encoding: .utf8) else {
            return nil
        }
        let normalizedTarget = normalizeMAC(matchingMAC)
        let blocks = content.components(separatedBy: "{")
        for block in blocks {
            var ipAddress: String?
            var hwAddress: String?
            for rawLine in block.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("ip_address=") {
                    ipAddress = String(line.dropFirst("ip_address=".count))
                } else if line.hasPrefix("hw_address=") {
                    let rawHW = String(line.dropFirst("hw_address=".count))
                    // format is usually "1,02:24:8a:..."
                    if let commaIdx = rawHW.firstIndex(of: ",") {
                        hwAddress = String(rawHW[rawHW.index(after: commaIdx)...])
                    } else {
                        hwAddress = rawHW
                    }
                }
            }
            if let ip = ipAddress, let hw = hwAddress, normalizeMAC(hw) == normalizedTarget {
                return ip
            }
        }
        return nil
    }

    private func normalizeMAC(_ mac: String) -> String {
        return mac.lowercased()
            .split(separator: ":")
            .map { segment in
                segment.count == 1 ? "0" + segment : String(segment)
            }
            .joined(separator: ":")
    }

    /// 绑定 bridge100 物理桥接网卡直连探测端口，彻底绕过本机 Clash/Surge TUN 虚拟网卡劫持导致的假阳性
    private func checkTCPPortDirect(host: String, port: Int, timeout: TimeInterval) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var ifIndex = if_nametoindex("bridge100")
        if ifIndex == 0 {
            ifIndex = if_nametoindex("bridge101")
        }
        if ifIndex != 0 {
            _ = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifIndex, socklen_t(MemoryLayout<UInt32>.size))
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            ensureLocalForwarder(targetHost: host, port: port)
            ensureAdditionalForwarders(targetHost: host, consolePort: port, ports: configuredPortsSnapshot())
            return true
        }
        guard errno == EINPROGRESS else {
            return false
        }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let timeoutMs = Int32(max(100, Int(timeout * 1000)))
        let pollRes = poll(&pfd, 1, timeoutMs)
        guard pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 else {
            return false
        }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 && soError == 0 {
            ensureLocalForwarder(targetHost: host, port: port)
            ensureAdditionalForwarders(targetHost: host, consolePort: port, ports: configuredPortsSnapshot())
            return true
        }
        return false
    }

    // MARK: - Local and LAN TCP forwarding to the NAT-connected guest
    private var forwarderListenFD: Int32 = -1
    private var forwardedTargetHost: String = ""
    private var forwardedPort: Int = 0
    private var forwarderBindHost: String = ""
    private var forwarderGeneration: UInt64 = 0
    private var additionalForwarders: [Int: AdditionalForwarder] = [:]
    private var additionalForwarderGeneration: UInt64 = 0
    private let forwarderLock = NSLock()

    private func configuredPortsSnapshot() -> [Int] {
        forwarderLock.lock()
        defer { forwarderLock.unlock() }
        return configuredForwardingPorts
    }

    private func ensureAdditionalForwarders(targetHost: String, consolePort: Int, ports: [Int]) {
        let desiredPorts = Set(ports.filter { (1...65535).contains($0) && $0 != consolePort })
        var listenersToStart: [(port: Int, entry: AdditionalForwarder)] = []

        forwarderLock.lock()
        let bindHost = lanAccessEnabled ? "0.0.0.0" : "127.0.0.1"
        for (port, entry) in Array(additionalForwarders) {
            guard !desiredPorts.contains(port) || entry.targetHost != targetHost || entry.bindHost != bindHost else { continue }
            _ = shutdown(entry.listenFD, SHUT_RDWR)
            close(entry.listenFD)
            additionalForwarders.removeValue(forKey: port)
        }

        for port in desiredPorts where additionalForwarders[port] == nil {
            let listenFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard listenFD >= 0 else { continue }

            var reuse: Int32 = 1
            _ = setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(UInt16(port).bigEndian)
            guard inet_pton(AF_INET, bindHost, &addr.sin_addr) == 1 else {
                close(listenFD)
                continue
            }

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0, listen(listenFD, 32) == 0 else {
                NSLog("[FnOS Manager] 无法监听附加端口 %d：%s", port, strerror(errno))
                close(listenFD)
                continue
            }

            additionalForwarderGeneration &+= 1
            let entry = AdditionalForwarder(
                listenFD: listenFD,
                targetHost: targetHost,
                bindHost: bindHost,
                generation: additionalForwarderGeneration
            )
            additionalForwarders[port] = entry
            listenersToStart.append((port, entry))
        }
        forwarderLock.unlock()

        for (port, entry) in listenersToStart {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                while let self = self,
                      self.isCurrentAdditionalForwarder(port: port, entry: entry) {
                    var clientAddr = sockaddr_in()
                    var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            accept(entry.listenFD, sockPtr, &clientLen)
                        }
                    }
                    guard clientFD >= 0 else { break }
                    DispatchQueue.global(qos: .userInitiated).async {
                        Self.bridgeClientConnection(clientFD: clientFD, targetHost: entry.targetHost, targetPort: port)
                    }
                }
            }
        }
    }

    private func isCurrentAdditionalForwarder(port: Int, entry: AdditionalForwarder) -> Bool {
        forwarderLock.lock()
        defer { forwarderLock.unlock() }
        guard let current = additionalForwarders[port] else { return false }
        return current.listenFD == entry.listenFD && current.generation == entry.generation
    }

    public func ensureLocalForwarder(targetHost: String, port: Int) {
        forwarderLock.lock()
        defer { forwarderLock.unlock() }

        let bindHost = lanAccessEnabled ? "0.0.0.0" : "127.0.0.1"
        if forwarderListenFD >= 0,
           forwardedTargetHost == targetHost,
           forwardedPort == port,
           forwarderBindHost == bindHost {
            return
        }

        if forwarderListenFD >= 0 {
            let oldFD = forwarderListenFD
            forwarderListenFD = -1
            forwarderGeneration &+= 1
            _ = shutdown(oldFD, SHUT_RDWR)
            close(oldFD)
        }

        forwardedTargetHost = targetHost
        forwardedPort = port
        forwarderBindHost = bindHost

        let listenFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard listenFD >= 0 else { return }

        var reuse: Int32 = 1
        _ = setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        guard inet_pton(AF_INET, bindHost, &addr.sin_addr) == 1 else {
            close(listenFD)
            return
        }

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0, listen(listenFD, 32) == 0 else {
            close(listenFD)
            return
        }

        forwarderListenFD = listenFD
        forwarderGeneration &+= 1
        let generation = forwarderGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let self = self, self.isCurrentForwarder(listenFD, generation: generation) {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        accept(listenFD, sockPtr, &clientLen)
                    }
                }
                guard clientFD >= 0 else { break }
                guard let (host, dstPort) = self.forwarderTarget(for: listenFD, generation: generation) else {
                    close(clientFD)
                    continue
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.bridgeClientConnection(clientFD: clientFD, targetHost: host, targetPort: dstPort)
                }
            }
        }
    }

    private func isCurrentForwarder(_ listenFD: Int32, generation: UInt64) -> Bool {
        forwarderLock.lock()
        defer { forwarderLock.unlock() }
        return forwarderListenFD == listenFD && forwarderGeneration == generation
    }

    private func forwarderTarget(for listenFD: Int32, generation: UInt64) -> (String, Int)? {
        forwarderLock.lock()
        defer { forwarderLock.unlock() }
        guard forwarderListenFD == listenFD, forwarderGeneration == generation else { return nil }
        return (forwardedTargetHost, forwardedPort)
    }

    private func stopLocalForwarder() {
        forwarderLock.lock()
        defer { forwarderLock.unlock() }

        if forwarderListenFD >= 0 {
            let listenFD = forwarderListenFD
            forwarderListenFD = -1
            forwarderGeneration &+= 1
            _ = shutdown(listenFD, SHUT_RDWR)
            close(listenFD)
        }
        for entry in additionalForwarders.values {
            _ = shutdown(entry.listenFD, SHUT_RDWR)
            close(entry.listenFD)
        }
        additionalForwarders.removeAll()
        forwardedTargetHost = ""
        forwardedPort = 0
        forwarderBindHost = ""
    }

    private static func bridgeClientConnection(clientFD: Int32, targetHost: String, targetPort: Int) {
        let upstreamFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard upstreamFD >= 0 else {
            close(clientFD)
            return
        }

        var ifIndex = if_nametoindex("bridge100")
        if ifIndex == 0 {
            ifIndex = if_nametoindex("bridge101")
        }
        if ifIndex != 0 {
            _ = setsockopt(upstreamFD, IPPROTO_IP, IP_BOUND_IF, &ifIndex, socklen_t(MemoryLayout<UInt32>.size))
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(targetPort).bigEndian)
        guard inet_pton(AF_INET, targetHost, &addr.sin_addr) == 1 else {
            close(upstreamFD)
            close(clientFD)
            return
        }

        let res = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(upstreamFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard res == 0 else {
            close(upstreamFD)
            close(clientFD)
            return
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.pipeData(from: clientFD, to: upstreamFD)
            shutdown(upstreamFD, SHUT_WR)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.pipeData(from: upstreamFD, to: clientFD)
            shutdown(clientFD, SHUT_WR)
            group.leave()
        }

        group.notify(queue: .global(qos: .utility)) {
            close(upstreamFD)
            close(clientFD)
        }
    }

    private static func pipeData(from srcFD: Int32, to dstFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let n = read(srcFD, &buffer, buffer.count)
            if n <= 0 { break }
            var offset = 0
            while offset < n {
                let written = buffer.withUnsafeBytes { rawBuf in
                    write(dstFD, rawBuf.baseAddress!.advanced(by: offset), n - offset)
                }
                if written <= 0 { return }
                offset += written
            }
        }
    }
}
