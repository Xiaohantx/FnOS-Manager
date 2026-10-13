import Foundation

public struct VMSettings: Codable, Equatable {
    public var cpuCount: Int
    public var memorySizeGB: Int
    public var diskSizeGB: Int
    public var dataDiskSizeGB: Int
    public var isoPath: String
    public var vmDataDirectory: String
    public var dataStorageDirectory: String
    public var attachISO: Bool
    public var isInstalled: Bool
    public var webPort: Int
    public var sharedFolders: [SharedFolder]
    public var language: AppLanguage
    public var dynamicOptimization: Bool
    public var customDomainPrefix: String
    public var isCustomDomainEnabled: Bool
    public var autoStartOnLogin: Bool
    public var bridgeNetworkMode: Bool

    public init(
        cpuCount: Int,
        memorySizeGB: Int,
        diskSizeGB: Int,
        dataDiskSizeGB: Int = 256,
        isoPath: String,
        vmDataDirectory: String,
        dataStorageDirectory: String? = nil,
        attachISO: Bool,
        isInstalled: Bool,
        webPort: Int = 5666,
        sharedFolders: [SharedFolder],
        language: AppLanguage = .zhHans,
        dynamicOptimization: Bool = true,
        customDomainPrefix: String = "nas",
        isCustomDomainEnabled: Bool = true,
        autoStartOnLogin: Bool = false,
        bridgeNetworkMode: Bool = true
    ) {
        self.cpuCount = cpuCount
        self.memorySizeGB = memorySizeGB
        self.diskSizeGB = diskSizeGB
        self.dataDiskSizeGB = dataDiskSizeGB
        self.isoPath = isoPath
        self.vmDataDirectory = vmDataDirectory
        self.dataStorageDirectory = dataStorageDirectory ?? vmDataDirectory
        self.attachISO = attachISO
        self.isInstalled = isInstalled
        self.webPort = webPort
        self.sharedFolders = sharedFolders
        self.language = language
        self.dynamicOptimization = dynamicOptimization
        self.customDomainPrefix = customDomainPrefix
        self.isCustomDomainEnabled = isCustomDomainEnabled
        self.autoStartOnLogin = autoStartOnLogin
        self.bridgeNetworkMode = bridgeNetworkMode
    }

    enum CodingKeys: String, CodingKey {
        case cpuCount, memorySizeGB, diskSizeGB, dataDiskSizeGB, isoPath, vmDataDirectory, dataStorageDirectory, attachISO, isInstalled, webPort, sharedFolders, language, dynamicOptimization, customDomainPrefix, isCustomDomainEnabled, autoStartOnLogin, bridgeNetworkMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpuCount = try container.decode(Int.self, forKey: .cpuCount)
        memorySizeGB = try container.decode(Int.self, forKey: .memorySizeGB)
        diskSizeGB = try container.decode(Int.self, forKey: .diskSizeGB)
        dataDiskSizeGB = try container.decodeIfPresent(Int.self, forKey: .dataDiskSizeGB) ?? 256
        isoPath = try container.decode(String.self, forKey: .isoPath)
        let decodedVMDir = try container.decode(String.self, forKey: .vmDataDirectory)
        vmDataDirectory = decodedVMDir
        dataStorageDirectory = try container.decodeIfPresent(String.self, forKey: .dataStorageDirectory) ?? decodedVMDir
        attachISO = try container.decode(Bool.self, forKey: .attachISO)
        isInstalled = try container.decode(Bool.self, forKey: .isInstalled)
        let decodedPort = try container.decodeIfPresent(Int.self, forKey: .webPort) ?? 5666
        webPort = (decodedPort == 5678) ? 5666 : decodedPort
        sharedFolders = try container.decode([SharedFolder].self, forKey: .sharedFolders)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zhHans
        dynamicOptimization = try container.decodeIfPresent(Bool.self, forKey: .dynamicOptimization) ?? true
        customDomainPrefix = try container.decodeIfPresent(String.self, forKey: .customDomainPrefix) ?? "nas"
        isCustomDomainEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCustomDomainEnabled) ?? true
        autoStartOnLogin = try container.decodeIfPresent(Bool.self, forKey: .autoStartOnLogin) ?? false
        bridgeNetworkMode = try container.decodeIfPresent(Bool.self, forKey: .bridgeNetworkMode) ?? true
    }

    public static let defaultISOUri = ""

    public static var defaultVMDataDir: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = appSupport?.appendingPathComponent("fnOS_Mac").path ?? "/Volumes/Han/AiProjectList/fnos/vm_data"
        return dir
    }

    public static var standardSharedFolders: [SharedFolder] {
        let sharedPath = "\(defaultVMDataDir)/Shared"
        try? FileManager.default.createDirectory(atPath: sharedPath, withIntermediateDirectories: true)
        return [
            SharedFolder(tag: "fnos_shared", hostPath: sharedPath, readOnly: false, isEnabled: true)
        ]
    }

    public static var `default`: VMSettings {
        let availableCPUs = max(2, min(ProcessInfo.processInfo.activeProcessorCount / 2, 8))
        return VMSettings(
            cpuCount: availableCPUs,
            memorySizeGB: 4,
            diskSizeGB: 64,
            dataDiskSizeGB: 256,
            isoPath: "",
            vmDataDirectory: defaultVMDataDir,
            attachISO: true,
            isInstalled: false,
            webPort: 5666,
            sharedFolders: standardSharedFolders
        )
    }

    private static let settingsKey = "com.fnnas.fnos.desktop.settings"

    public static func load() -> VMSettings {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(VMSettings.self, from: data) {
            return decoded
        }
        return .default
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: VMSettings.settingsKey)
        }
    }
}
