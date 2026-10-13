import Foundation

public struct SharedFolder: Identifiable, Codable, Equatable {
    public var id: UUID
    public var tag: String
    public var hostPath: String
    public var readOnly: Bool
    public var isEnabled: Bool

    public init(id: UUID = UUID(), tag: String, hostPath: String, readOnly: Bool = false, isEnabled: Bool = true) {
        self.id = id
        self.tag = tag
        self.hostPath = hostPath
        self.readOnly = readOnly
        self.isEnabled = isEnabled
    }

    /// Linux/fnOS mount command preview
    public var mountCommand: String {
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return "sudo mkdir -p /mnt/\(cleanTag) && sudo mount -t virtiofs \(cleanTag) /mnt/\(cleanTag)"
    }

    public var displayName: String {
        let name = URL(fileURLWithPath: hostPath).lastPathComponent
        let lower = tag.lowercased()
        if lower == "downloads" { return "Downloads" }
        if lower == "documents" { return "Documents" }
        if lower == "pictures" { return "Pictures" }
        if lower == "project_files" || lower == "projects" { return "Project Files" }
        return name.isEmpty ? tag : name
    }

    public func localizedName(for language: AppLanguage) -> String {
        let lower = tag.lowercased()
        if lower == "downloads" { return language.strings.folderDownloads }
        if lower == "documents" { return language.strings.folderDocuments }
        if lower == "pictures" { return language.strings.folderPictures }
        if lower == "project_files" || lower == "projects" { return language.strings.folderProjects }
        let name = URL(fileURLWithPath: hostPath).lastPathComponent
        return name.isEmpty ? tag : name
    }

    public var iconGlyph: String {
        let lower = tag.lowercased()
        if lower.contains("download") { return "arrow.down" }
        if lower.contains("doc") { return "doc.text" }
        if lower.contains("pic") || lower.contains("photo") { return "photo" }
        if lower.contains("proj") || lower.contains("code") { return "folder.fill" }
        return "folder"
    }
}

