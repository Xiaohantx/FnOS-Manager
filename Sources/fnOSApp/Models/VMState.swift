import Foundation

public enum VMStatus: String, Codable {
    case stopped = "已停止"
    case starting = "正在启动..."
    case installing = "安装引导中"
    case running = "运行中"
    case paused = "已挂起暂停"
    case stopping = "正在关机..."
    case error = "运行异常"

    public var isRunningOrStarting: Bool {
        return self == .starting || self == .installing || self == .running || self == .paused
    }

    public var statusColorName: String {
        switch self {
        case .stopped: return "gray"
        case .starting, .installing, .stopping: return "orange"
        case .running: return "green"
        case .paused: return "yellow"
        case .error: return "red"
        }
    }
}

