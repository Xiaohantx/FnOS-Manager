import SwiftUI
import AppKit

public struct SharedFoldersView: View {
    @ObservedObject var vmManager: VMManager
    @State private var showingAddAlert = false
    @State private var newTag = ""
    @State private var newPath = ""
    @State private var newReadOnly = false
    @State private var copiedNotice = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac 本地文件夹挂载 (VirtIO-FS)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("通过 Apple 原生高性能 VirtIO-FS 技术，将 Mac 文件夹以近乎裸机磁盘的速度共享给 fnOS。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: selectFolderFromMac) {
                    Label("添加 Mac 文件夹", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 8)

            // Folders List
            if vmManager.settings.sharedFolders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("尚未添加任何共享文件夹")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("点击右上角「添加 Mac 文件夹」，选择你想要让飞牛访问的本地目录（例如影视、音乐、下载等）。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                List {
                    ForEach($vmManager.settings.sharedFolders) { $folder in
                        HStack(spacing: 16) {
                            Image(systemName: "folder.fill")
                                .font(.title2)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(URL(fileURLWithPath: folder.hostPath).lastPathComponent)
                                        .font(.headline)
                                    Text("标签: \(folder.tag)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                Text(folder.hostPath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Toggle("只读", isOn: $folder.readOnly)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .onChange(of: folder.readOnly) { _, _ in
                                    vmManager.settings.save()
                                }

                            Toggle("", isOn: $folder.isEnabled)
                                .toggleStyle(.switch)
                                .onChange(of: folder.isEnabled) { _, _ in
                                    vmManager.settings.save()
                                }

                            Button(role: .destructive) {
                                deleteFolder(folder)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset)
                .cornerRadius(8)
            }

            // Usage Guide Box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.orange)
                    Text("fnOS 虚拟机内挂载说明")
                        .font(.headline)
                    Spacer()
                    Button(copiedNotice ? "已复制!" : "复制全部挂载命令") {
                        copyAllMountCommands()
                    }
                    .controlSize(.small)
                }

                Text("在飞牛系统的终端或 SSH 中运行以下命令，即可直接访问 Mac 目录：")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(vmManager.settings.sharedFolders.filter { $0.isEnabled }) { folder in
                            Text(folder.mountCommand)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        if vmManager.settings.sharedFolders.filter({ $0.isEnabled }).isEmpty {
                            Text("# 暂无启用的挂载目录")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }

                Text("提示：修改挂载配置后，需要重启虚拟机以使 VirtIO 设备更新。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(20)
    }

    private func selectFolderFromMac() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择挂载文件夹"

        if panel.runModal() == .OK, let url = panel.url {
            let folderName = url.lastPathComponent
            // Generate clean alphanumeric tag
            var cleanTag = folderName.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            if cleanTag.isEmpty { cleanTag = "mac_share" }

            // Ensure unique tag
            var finalTag = cleanTag
            var counter = 1
            while vmManager.settings.sharedFolders.contains(where: { $0.tag == finalTag }) {
                finalTag = "\(cleanTag)_\(counter)"
                counter += 1
            }

            let newFolder = SharedFolder(
                tag: finalTag,
                hostPath: url.path,
                readOnly: false,
                isEnabled: true
            )
            vmManager.settings.sharedFolders.append(newFolder)
            vmManager.settings.save()
        }
    }

    private func deleteFolder(_ folder: SharedFolder) {
        vmManager.settings.sharedFolders.removeAll { $0.id == folder.id }
        vmManager.settings.save()
    }

    private func copyAllMountCommands() {
        let commands = vmManager.settings.sharedFolders
            .filter { $0.isEnabled }
            .map { $0.mountCommand }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands, forType: .string)

        copiedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedNotice = false
        }
    }
}
