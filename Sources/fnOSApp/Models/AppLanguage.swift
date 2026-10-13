import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case zhHans = "zh-Hans"
    case en = "en"
    case zhHant = "zh-Hant"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .zhHant: return "繁體中文"
        }
    }

    public var strings: LocalizedStrings {
        switch self {
        case .zhHans:
            return LocalizedStrings(
                appTitle: "FnOS Manager",
                onlinePrefix: "在线",
                offline: "离线",
                booting: "启动中...",
                stopping: "正在停止...",
                installing: "安装中...",
                error: "异常",
                runButton: "启动",
                stopButton: "停止",
                openSafariHelp: "在 Safari 浏览器中打开控制台",
                systemNotice: "系统提示",
                confirm: "确定",

                tabWeb: "控制台",
                tabStorage: "存储空间",
                tabDisplay: "底层屏幕",
                tabSettings: "系统设置",

                systemBootDisk: "系统引导盘",
                systemDiskSubtitle: "NVMe SSD - 64 GB",
                usedWord: "已用",
                freeWord: "可用",
                apfsSparseBadge: "APFS 稀疏动态扩容",
                dataPoolDisk: "主数据存储盘",
                dataDiskSubtitle: "飞牛数据池 - %d GB (/dev/vdb)",
                raidStatus: "RAID: 就绪状态",
                dataDiskHint: "已挂载数据盘(/dev/vdb)，进入飞牛控制台「存储空间」即可创建。",
                virtioSharedFolders: "VirtIO-FS 共享文件夹",
                mappedMacFolders: "已挂载的 Mac 目录：",
                addButton: "添加",
                revealInFinder: "在访达中显示",
                removeShare: "移除挂载",

                folderDownloads: "下载",
                folderDocuments: "文档",
                folderPictures: "图片",
                folderProjects: "项目工程",

                webNotRunning: "飞牛私有云未在运行",
                webStarting: "正在启动飞牛后台服务...",
                webDetectingNet: "正在检测网络与端口响应（通常需 15~25 秒）...",
                webStartGuide: "点击右上角「启动 ▶」启动系统，即可在此直接操作飞牛桌面。",
                startSystemBtn: "启动系统 ▶",

                languageSection: "界面语言",
                languageSubtitle: "切换管理器的多语言显示环境",
                hardwareSection: "硬件资源配置",
                cpuCoresLabel: "CPU 核心数",
                memoryLabel: "内存分配",
                dataDiskSizeLabel: "数据盘容量",
                isoSection: "系统安装镜像",
                changeISOButton: "更换 ISO...",
                arm64VerifiedBadge: "ARM64 原生架构已验证",
                selectISOPrompt: "选择 ISO 安装镜像",
                selectFolderPrompt: "选择挂载文件夹",
                archIncompatibleTitle: "架构不兼容提示",
                archIncompatibleMessage: "您所选择的镜像是 Intel / PC (x86_64) 版本，无法在 Apple Silicon (ARM64) Mac 上运行。\n\n请使用飞牛官方发布的 UEFI ARM 镜像。",

                fetchISOHeader: "官方 ARM 镜像获取",
                fetchISOButton: "获取官方镜像",
                fetchingInfo: "正在从 fnnas.com 获取最新镜像与 MD5...",
                isoNameLabel: "镜像名称",
                directUrlLabel: "直接下载链接",
                md5Label: "MD5 校验和",
                copyLinkBtn: "复制链接",
                copyMD5Btn: "复制 MD5",
                openInBrowserBtn: "浏览器直接下载",
                startDownloadBtn: "下载到本地",
                officialVerified: "官方校验已匹配",
                localFileFound: "本地已检测到此镜像",
                useAsCurrentISO: "设为当前启动镜像",

                // 极简设置重构
                smartISOCardTitle: "fnOS 官方 ARM64 安装镜像",
                smartISOCardSubtitle: "支持 Apple M系列芯片虚拟化 · 自动匹配官方安全校验",
                isoReadyBadge: "已就绪",
                isoDetailsToggle: "详情与校验",
                checkOfficialLatest: "检查官方最新",
                customISOPick: "选择自定义 ISO...",
                hardwarePresetSection: "虚拟机规格与性能",
                hardwareAdaptiveMac: "（已适配当前 Mac: Apple M系列）",
                presetZeroMathHint: "开箱即用，无需繁琐计算",
                presetLightTitle: "🍃 轻量节能",
                presetLightDesc: "2 核 CPU · 4 GB 内存\n适合轻度文件共享与静默备份",
                presetBalancedTitle: "⚡️ 标准平衡",
                presetBalancedDesc: "4 核 CPU · 8 GB 内存\n兼顾相册AI、影音串流与流畅度",
                presetBalancedTag: "推荐",
                presetPowerTitle: "🚀 性能狂飙",
                presetPowerDesc: "6 核 CPU · 16 GB 内存\n适合多 Docker 容器与高并发任务",
                sparseDiskHint: "主数据盘: 256 GB 稀疏动态扩容 (用多少占多少 Mac 硬盘空间)",
                advancedCustomToggle: "高级微调...",
                autoSaveHint: "所有设置自动即时生效保存",
                dynamicOptimizationHint: "VirtIO 动态内存回垦 · I/O 缓存加速 · 硬件熵池",

                developerSection: "开源项目与主页",
                developerSubtitle: "GitHub: https://github.com/Xiaohantx/FnOS-Manager",
                visitGithubBtn: "访问 GitHub 主页"
            )

        case .en:
            return LocalizedStrings(
                appTitle: "FnOS Manager",
                onlinePrefix: "Online",
                offline: "Offline",
                booting: "Booting...",
                stopping: "Stopping...",
                installing: "Installing...",
                error: "Error",
                runButton: "Run",
                stopButton: "Stop",
                openSafariHelp: "Open Web Console in Safari",
                systemNotice: "System Notice",
                confirm: "OK",

                tabWeb: "Web Console",
                tabStorage: "Storage Pools",
                tabDisplay: "VM Display",
                tabSettings: "Settings",

                systemBootDisk: "System Boot Disk",
                systemDiskSubtitle: "NVMe SSD - 64 GB",
                usedWord: "Used",
                freeWord: "Free",
                apfsSparseBadge: "APFS Sparse Allocation",
                dataPoolDisk: "Data Pool Disk",
                dataDiskSubtitle: "fnOS Data Pool - %d GB (/dev/vdb)",
                raidStatus: "RAID: Ready Status",
                dataDiskHint: "Secondary disk attached (/dev/vdb). Create storage pool in fnOS console.",
                virtioSharedFolders: "VirtIO-FS Shared Folders",
                mappedMacFolders: "Mapped Mac Folders:",
                addButton: "Add",
                revealInFinder: "Reveal in Finder",
                removeShare: "Remove Share",

                folderDownloads: "Downloads",
                folderDocuments: "Documents",
                folderPictures: "Pictures",
                folderProjects: "Project Files",

                webNotRunning: "fnOS is not running",
                webStarting: "Starting fnOS background services...",
                webDetectingNet: "Checking network and port response (approx. 15~25s)...",
                webStartGuide: "Click 'Run ▶' to start the system and operate the console directly.",
                startSystemBtn: "Start System Run ▶",

                languageSection: "Display Language",
                languageSubtitle: "Switch application interface language",
                hardwareSection: "Hardware Configuration",
                cpuCoresLabel: "CPU Cores",
                memoryLabel: "Memory",
                dataDiskSizeLabel: "Data Disk Size",
                isoSection: "System ISO Image",
                changeISOButton: "Change ISO...",
                arm64VerifiedBadge: "ARM64 Native Verified",
                selectISOPrompt: "Select ISO Image",
                selectFolderPrompt: "Select Folder to Mount",
                archIncompatibleTitle: "Architecture Incompatibility",
                archIncompatibleMessage: "The selected ISO image is for Intel / PC (x86_64) and cannot run on Apple Silicon (ARM64) Mac.\n\nPlease select the official UEFI ARM ISO.",

                fetchISOHeader: "Official ARM ISO Download",
                fetchISOButton: "Fetch Official ISO",
                fetchingInfo: "Fetching latest ISO & MD5 from fnnas.com...",
                isoNameLabel: "Image Name",
                directUrlLabel: "Direct Download URL",
                md5Label: "MD5 Checksum",
                copyLinkBtn: "Copy Link",
                copyMD5Btn: "Copy MD5",
                openInBrowserBtn: "Browser Direct Download",
                startDownloadBtn: "Download to Mac",
                officialVerified: "Official Verified",
                localFileFound: "Local Image Detected",
                useAsCurrentISO: "Set as Active ISO",

                // Minimalist settings redesign
                smartISOCardTitle: "fnOS Official ARM64 Image",
                smartISOCardSubtitle: "Supports Apple Silicon Virtualization · Auto-verified checksum",
                isoReadyBadge: "Ready",
                isoDetailsToggle: "Details & Hash",
                checkOfficialLatest: "Check Latest",
                customISOPick: "Select Custom ISO...",
                hardwarePresetSection: "VM Hardware & Performance",
                hardwareAdaptiveMac: "(Optimized for Apple Silicon)",
                presetZeroMathHint: "Out of the box, zero calculation",
                presetLightTitle: "🍃 Lightweight",
                presetLightDesc: "2 Cores · 4 GB RAM\nFor silent file sync and backup",
                presetBalancedTitle: "⚡️ Balanced",
                presetBalancedDesc: "4 Cores · 8 GB RAM\nFor AI photos, media streaming & fluid NAS",
                presetBalancedTag: "Recommended",
                presetPowerTitle: "🚀 High Performance",
                presetPowerDesc: "6 Cores · 16 GB RAM\nFor heavy Docker containers & multi-tasking",
                sparseDiskHint: "Data Disk: 256 GB Sparse Allocation (uses only actual space on Mac)",
                advancedCustomToggle: "Advanced...",
                autoSaveHint: "All settings saved and applied automatically",
                dynamicOptimizationHint: "VirtIO Dynamic Ballooning · Cached I/O · Hardware Entropy",

                developerSection: "Open Source & Developer",
                developerSubtitle: "GitHub: https://github.com/Xiaohantx/FnOS-Manager",
                visitGithubBtn: "Visit GitHub Profile"
            )

        case .zhHant:
            return LocalizedStrings(
                appTitle: "FnOS Manager",
                onlinePrefix: "已連線",
                offline: "離線",
                booting: "啟動中...",
                stopping: "正在停止...",
                installing: "安裝中...",
                error: "異常",
                runButton: "啟動",
                stopButton: "停止",
                openSafariHelp: "在 Safari 瀏覽器中打開控制台",
                systemNotice: "系統提示",
                confirm: "確定",

                tabWeb: "控制台",
                tabStorage: "儲存空間",
                tabDisplay: "底層螢幕",
                tabSettings: "系統設定",

                systemBootDisk: "系統開機盤",
                systemDiskSubtitle: "NVMe SSD - 64 GB",
                usedWord: "已用",
                freeWord: "可用",
                apfsSparseBadge: "APFS 稀疏動態擴充",
                dataPoolDisk: "主資料儲存盤",
                dataDiskSubtitle: "飛牛資料池 - %d GB (/dev/vdb)",
                raidStatus: "RAID: 就緒狀態",
                dataDiskHint: "已掛載資料盤(/dev/vdb)，進入飛牛控制台「儲存空間」即可建立。",
                virtioSharedFolders: "VirtIO-FS 共享資料夾",
                mappedMacFolders: "已掛載的 Mac 目錄：",
                addButton: "新增",
                revealInFinder: "在訪達中顯示",
                removeShare: "移除掛載",

                folderDownloads: "下載",
                folderDocuments: "文件",
                folderPictures: "圖片",
                folderProjects: "專案工程",

                webNotRunning: "飛牛私有雲未在運行",
                webStarting: "正在啟動飛牛後台服務...",
                webDetectingNet: "正在檢測網路與連接埠響應（通常需 15~25 秒）...",
                webStartGuide: "點擊右上角「啟動 ▶」啟動系統，即可在此直接操作飛牛桌面。",
                startSystemBtn: "啟動系統 啟動 ▶",

                languageSection: "介面語言",
                languageSubtitle: "切換管理器的多語言顯示環境",
                hardwareSection: "硬體資源配置",
                cpuCoresLabel: "CPU 核心數",
                memoryLabel: "記憶體分配",
                dataDiskSizeLabel: "資料盤容量",
                isoSection: "系統安裝映像",
                changeISOButton: "更換 ISO...",
                arm64VerifiedBadge: "ARM64 原生架構已驗證",
                selectISOPrompt: "選擇 ISO 安裝映像",
                selectFolderPrompt: "選擇掛載資料夾",
                archIncompatibleTitle: "架構不相容提示",
                archIncompatibleMessage: "您所選擇的映像是 Intel / PC (x86_64) 版本，無法在 Apple Silicon (ARM64) Mac 上運行。\n\n請使用飛牛官方發布的 UEFI ARM 映像。",

                fetchISOHeader: "官方 ARM 映像取得",
                fetchISOButton: "取得官方映像",
                fetchingInfo: "正在從 fnnas.com 取得最新映像與 MD5...",
                isoNameLabel: "映像名稱",
                directUrlLabel: "直接下載連結",
                md5Label: "MD5 校驗和",
                copyLinkBtn: "複製連結",
                copyMD5Btn: "複製 MD5",
                openInBrowserBtn: "瀏覽器直接下載",
                startDownloadBtn: "下載至本地",
                officialVerified: "官方校驗已匹配",
                localFileFound: "本地已檢測到此映像",
                useAsCurrentISO: "設為目前啟動映像",

                // 極簡設置重構
                smartISOCardTitle: "fnOS 官方 ARM64 安裝映像",
                smartISOCardSubtitle: "支援 Apple M系列晶片虛擬化 · 自動匹配官方安全校驗",
                isoReadyBadge: "已就緒",
                isoDetailsToggle: "詳情與校驗",
                checkOfficialLatest: "檢查官方最新",
                customISOPick: "選擇自訂 ISO...",
                hardwarePresetSection: "虛擬機器規格與效能",
                hardwareAdaptiveMac: "（已適配目前 Mac: Apple M系列）",
                presetZeroMathHint: "開箱即用，無需繁瑣計算",
                presetLightTitle: "🍃 輕量節能",
                presetLightDesc: "2 核 CPU · 4 GB 記憶體\n適合輕度檔案共享與靜默備份",
                presetBalancedTitle: "⚡️ 標準平衡",
                presetBalancedDesc: "4 核 CPU · 8 GB 記憶體\n兼顧相簿AI、影音串流與流暢度",
                presetBalancedTag: "推薦",
                presetPowerTitle: "🚀 效能狂飆",
                presetPowerDesc: "6 核 CPU · 16 GB 記憶體\n適合多 Docker 容器與高並發任務",
                sparseDiskHint: "主資料盤: 256 GB 稀疏動態擴充 (用多少占多少 Mac 硬碟空間)",
                advancedCustomToggle: "進階微調...",
                autoSaveHint: "所有設定自動即時生效儲存",
                dynamicOptimizationHint: "VirtIO 動態記憶體回墾 · I/O 快取加速 · 硬體熵池",

                developerSection: "開源專案與首頁",
                developerSubtitle: "GitHub: https://github.com/Xiaohantx/FnOS-Manager",
                visitGithubBtn: "造訪 GitHub 首頁"
            )
        }
    }
}

public struct LocalizedStrings {
    // Header & Global
    public let appTitle: String
    public let onlinePrefix: String
    public let offline: String
    public let booting: String
    public let stopping: String
    public let installing: String
    public let error: String
    public let runButton: String
    public let stopButton: String
    public let openSafariHelp: String
    public let systemNotice: String
    public let confirm: String

    // Tabs
    public let tabWeb: String
    public let tabStorage: String
    public let tabDisplay: String
    public let tabSettings: String

    // Storage Pools
    public let systemBootDisk: String
    public let systemDiskSubtitle: String
    public let usedWord: String
    public let freeWord: String
    public let apfsSparseBadge: String
    public let dataPoolDisk: String
    public let dataDiskSubtitle: String
    public let raidStatus: String
    public let dataDiskHint: String
    public let virtioSharedFolders: String
    public let mappedMacFolders: String
    public let addButton: String
    public let revealInFinder: String
    public let removeShare: String

    // Standard Folders
    public let folderDownloads: String
    public let folderDocuments: String
    public let folderPictures: String
    public let folderProjects: String

    // Web Console
    public let webNotRunning: String
    public let webStarting: String
    public let webDetectingNet: String
    public let webStartGuide: String
    public let startSystemBtn: String

    // Settings
    public let languageSection: String
    public let languageSubtitle: String
    public let hardwareSection: String
    public let cpuCoresLabel: String
    public let memoryLabel: String
    public let dataDiskSizeLabel: String
    public let isoSection: String
    public let changeISOButton: String
    public let arm64VerifiedBadge: String
    public let selectISOPrompt: String
    public let selectFolderPrompt: String
    public let archIncompatibleTitle: String
    public let archIncompatibleMessage: String

    // ISO Fetcher & MD5
    public let fetchISOHeader: String
    public let fetchISOButton: String
    public let fetchingInfo: String
    public let isoNameLabel: String
    public let directUrlLabel: String
    public let md5Label: String
    public let copyLinkBtn: String
    public let copyMD5Btn: String
    public let openInBrowserBtn: String
    public let startDownloadBtn: String
    public let officialVerified: String
    public let localFileFound: String
    public let useAsCurrentISO: String

    // Minimalist Redesign
    public let smartISOCardTitle: String
    public let smartISOCardSubtitle: String
    public let isoReadyBadge: String
    public let isoDetailsToggle: String
    public let checkOfficialLatest: String
    public let customISOPick: String
    public let hardwarePresetSection: String
    public let hardwareAdaptiveMac: String
    public let presetZeroMathHint: String
    public let presetLightTitle: String
    public let presetLightDesc: String
    public let presetBalancedTitle: String
    public let presetBalancedDesc: String
    public let presetBalancedTag: String
    public let presetPowerTitle: String
    public let presetPowerDesc: String
    public let sparseDiskHint: String
    public let advancedCustomToggle: String
    public let autoSaveHint: String
    public let dynamicOptimizationHint: String

    // Developer / GitHub
    public let developerSection: String
    public let developerSubtitle: String
    public let visitGithubBtn: String
}
