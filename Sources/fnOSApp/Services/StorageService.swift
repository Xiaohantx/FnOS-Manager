import Foundation
import Virtualization
import Darwin

public enum StorageError: LocalizedError {
    case directoryCreationFailed(String)
    case diskCreationFailed(String)
    case variableStoreFailed(String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let msg): return "创建数据目录失败: \(msg)"
        case .diskCreationFailed(let msg): return "创建虚拟磁盘失败: \(msg)"
        case .variableStoreFailed(let msg): return "创建 EFI 变量存储失败: \(msg)"
        }
    }
}

public class StorageService {
    public static let shared = StorageService()

    private init() {}

    public func ensureDirectory(at path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw StorageError.directoryCreationFailed(error.localizedDescription)
            }
        }
        return url
    }

    public func ensureSparseDisk(directory: URL, fileName: String = "fnos_system.raw", sizeGB: Int) throws -> URL {
        let diskURL = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: diskURL.path) {
            let fd = open(diskURL.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
            guard fd >= 0 else {
                let err = String(cString: strerror(errno))
                throw StorageError.diskCreationFailed("无法打开/创建文件: \(err)")
            }
            defer { close(fd) }

            let targetBytes = off_t(sizeGB) * 1024 * 1024 * 1024
            if ftruncate(fd, targetBytes) != 0 {
                let err = String(cString: strerror(errno))
                throw StorageError.diskCreationFailed("ftruncate 调整稀疏文件失败: \(err)")
            }
        }
        return diskURL
    }

    public func ensureDataDisk(directory: URL, fileName: String = "fnos_data.raw", sizeGB: Int = 256) throws -> URL {
        _ = try ensureDirectory(at: directory.path)
        let diskURL = directory.appendingPathComponent(fileName)
        let targetBytes = off_t(sizeGB) * 1024 * 1024 * 1024

        if !FileManager.default.fileExists(atPath: diskURL.path) {
            let fd = open(diskURL.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
            guard fd >= 0 else {
                let err = String(cString: strerror(errno))
                throw StorageError.diskCreationFailed("无法打开/创建数据盘文件: \(err)")
            }
            defer { close(fd) }

            if ftruncate(fd, targetBytes) != 0 {
                let err = String(cString: strerror(errno))
                throw StorageError.diskCreationFailed("ftruncate 调整数据盘失败: \(err)")
            }
        } else {
            var st = stat()
            if stat(diskURL.path, &st) == 0 {
                let allocatedBytes = Int64(st.st_blocks) * 512
                let virtualBytes = st.st_size
                let isUnformatted = allocatedBytes < 50 * 1024 * 1024
                if virtualBytes != targetBytes && (isUnformatted || targetBytes > virtualBytes) {
                    let fd = open(diskURL.path, O_RDWR)
                    if fd >= 0 {
                        _ = ftruncate(fd, targetBytes)
                        close(fd)
                    }
                }
            }
        }
        return diskURL
    }

    /// 迁移数据存储目录：将旧目录中的 fnos_data.raw 与 Shared 文件夹完整迁移至新目录，并删除旧目录中的原数据文件
    public func migrateDataStorage(from oldDirPath: String, to newDirPath: String, sizeGB: Int) throws {
        let fm = FileManager.default
        let oldDirURL = URL(fileURLWithPath: oldDirPath).standardizedFileURL
        let newDirURL = URL(fileURLWithPath: newDirPath).standardizedFileURL

        _ = try ensureDirectory(at: newDirURL.path)

        guard oldDirURL.path != newDirURL.path else {
            _ = try ensureDataDisk(directory: newDirURL, sizeGB: sizeGB)
            return
        }

        let oldDiskURL = oldDirURL.appendingPathComponent("fnos_data.raw")
        let newDiskURL = newDirURL.appendingPathComponent("fnos_data.raw")

        if fm.fileExists(atPath: oldDiskURL.path) {
            var oldStat = stat()
            var newDirStat = stat()
            let hasOldStat = (stat(oldDiskURL.path, &oldStat) == 0)
            let hasNewDirStat = (stat(newDirURL.path, &newDirStat) == 0)

            if hasOldStat && hasNewDirStat && oldStat.st_dev == newDirStat.st_dev {
                // 同一磁盘分区：直接原子级移动文件，瞬间完成且保留稀疏结构
                if fm.fileExists(atPath: newDiskURL.path) {
                    try? fm.removeItem(at: newDiskURL)
                }
                try fm.moveItem(at: oldDiskURL, to: newDiskURL)
                _ = try ensureDataDisk(directory: newDirURL, sizeGB: sizeGB)
            } else if hasOldStat && (Int64(oldStat.st_blocks) * 512 == 0) {
                // 跨分区且原数据盘尚未写入任何实际数据块：直接在新目录创建稀疏盘并删除旧文件
                if fm.fileExists(atPath: newDiskURL.path) {
                    try? fm.removeItem(at: newDiskURL)
                }
                _ = try ensureDataDisk(directory: newDirURL, sizeGB: sizeGB)
                try? fm.removeItem(at: oldDiskURL)
            } else {
                // 跨分区且包含有效数据块：使用 SEEK_DATA / SEEK_HOLE 稀疏块迁移并在完成后删除旧文件
                try copySparseDiskFile(from: oldDiskURL, to: newDiskURL, targetSizeGB: sizeGB)
                try? fm.removeItem(at: oldDiskURL)
            }
        } else {
            _ = try ensureDataDisk(directory: newDirURL, sizeGB: sizeGB)
        }

        // 迁移 Shared 共享文件夹内容并清理旧目录中的 Shared
        let oldSharedURL = oldDirURL.appendingPathComponent("Shared")
        let newSharedURL = newDirURL.appendingPathComponent("Shared")
        try? fm.createDirectory(at: newSharedURL, withIntermediateDirectories: true)

        if fm.fileExists(atPath: oldSharedURL.path) {
            if let items = try? fm.contentsOfDirectory(atPath: oldSharedURL.path) {
                for item in items {
                    let srcItem = oldSharedURL.appendingPathComponent(item)
                    let dstItem = newSharedURL.appendingPathComponent(item)
                    if fm.fileExists(atPath: dstItem.path) {
                        try? fm.removeItem(at: dstItem)
                    }
                    if (try? fm.moveItem(at: srcItem, to: dstItem)) == nil {
                        try? fm.copyItem(at: srcItem, to: dstItem)
                        try? fm.removeItem(at: srcItem)
                    }
                }
            }
            try? fm.removeItem(at: oldSharedURL)
        }
    }

    private func copySparseDiskFile(from srcURL: URL, to dstURL: URL, targetSizeGB: Int) throws {
        let srcFD = open(srcURL.path, O_RDONLY)
        guard srcFD >= 0 else {
            throw StorageError.diskCreationFailed("无法读取原数据盘: \(String(cString: strerror(errno)))")
        }
        defer { close(srcFD) }

        var srcStat = stat()
        guard fstat(srcFD, &srcStat) == 0 else {
            throw StorageError.diskCreationFailed("无法获取原数据盘大小")
        }
        let srcSize = srcStat.st_size
        let targetBytes = max(srcSize, off_t(targetSizeGB) * 1024 * 1024 * 1024)

        let dstFD = open(dstURL.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        guard dstFD >= 0 else {
            throw StorageError.diskCreationFailed("无法在新目录创建数据盘: \(String(cString: strerror(errno)))")
        }
        defer { close(dstFD) }

        guard ftruncate(dstFD, targetBytes) == 0 else {
            throw StorageError.diskCreationFailed("新目录空间不足或调整稀疏文件大小失败")
        }

        let chunkSize = 4 * 1024 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 4096)
        defer { buffer.deallocate() }

        var offset: off_t = 0
        while offset < srcSize {
            let dataStart = lseek(srcFD, offset, SEEK_DATA)
            if dataStart < 0 {
                if errno == ENXIO {
                    break // 后续全部为空洞，无需复制
                }
                // 文件系统不支持 SEEK_DATA 时回退到当前 offset
                break
            }
            var dataEnd = lseek(srcFD, dataStart, SEEK_HOLE)
            if dataEnd < 0 || dataEnd > srcSize {
                dataEnd = srcSize
            }

            var cur = dataStart
            while cur < dataEnd {
                let toRead = min(Int(dataEnd - cur), chunkSize)
                let bytesRead = pread(srcFD, buffer, toRead, cur)
                if bytesRead <= 0 { break }

                var written = 0
                while written < bytesRead {
                    let w = pwrite(dstFD, buffer.advanced(by: written), bytesRead - written, cur + off_t(written))
                    if w <= 0 {
                        throw StorageError.diskCreationFailed("写入新数据盘失败: \(String(cString: strerror(errno)))")
                    }
                    written += w
                }
                cur += off_t(bytesRead)
            }
            offset = dataEnd
        }

        _ = fsync(dstFD)
    }

    public func isDiskInstalled(url: URL) -> Bool {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return false }
        let allocatedMB = (Int64(st.st_blocks) * 512) / (1024 * 1024)
        guard allocatedMB >= 500 else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2048), data.count >= 1024 else { return false }
        return data.contains { $0 != 0 }
    }

    public func ensureEFIVariableStore(directory: URL, fileName: String = "nvram.bin", recreate: Bool = false) throws -> VZEFIVariableStore {
        let nvramURL = directory.appendingPathComponent(fileName)
        if recreate {
            try? FileManager.default.removeItem(at: nvramURL)
        }
        if FileManager.default.fileExists(atPath: nvramURL.path) {
            return VZEFIVariableStore(url: nvramURL)
        } else {
            do {
                return try VZEFIVariableStore(creatingVariableStoreAt: nvramURL, options: .allowOverwrite)
            } catch {
                throw StorageError.variableStoreFailed(error.localizedDescription)
            }
        }
    }

    public func ensureMachineIdentifier(directory: URL, fileName: String = "machine_id.bin") -> VZGenericMachineIdentifier {
        let fileURL = directory.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: fileURL),
           let id = VZGenericMachineIdentifier(dataRepresentation: data) {
            return id
        }
        let newID = VZGenericMachineIdentifier()
        try? newID.dataRepresentation.write(to: fileURL)
        return newID
    }

    public func ensureMACAddress(directory: URL, fileName: String = "mac_address.txt") -> VZMACAddress {
        let fileURL = directory.appendingPathComponent(fileName)
        if let preferredStr = HostsManager.shared.preferredMACForCurrentHosts(),
           let preferredMAC = VZMACAddress(string: preferredStr) {
            try? preferredMAC.string.write(to: fileURL, atomically: true, encoding: .utf8)
            return preferredMAC
        }
        if let str = try? String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let mac = VZMACAddress(string: str) {
            return mac
        }
        let newMAC = VZMACAddress.randomLocallyAdministered()
        try? newMAC.string.write(to: fileURL, atomically: true, encoding: .utf8)
        return newMAC
    }

    public enum ISOArchitecture: Equatable {
        case arm64
        case x86_64
        case notBootable
        case fileNotFound
    }

    public func detectISOArchitecture(path: String) -> ISOArchitecture {
        guard FileManager.default.fileExists(atPath: path) else { return .fileNotFound }

        let procARM = Process()
        procARM.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        procARM.arguments = ["-tf", path, "EFI/boot/bootaa64.efi"]
        procARM.standardOutput = Pipe()
        procARM.standardError = Pipe()
        do {
            try procARM.run()
            procARM.waitUntilExit()
            if procARM.terminationStatus == 0 {
                return .arm64
            }
        } catch {
            return .notBootable
        }

        let procX86 = Process()
        procX86.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        procX86.arguments = ["-tf", path, "EFI/boot/bootx64.efi"]
        procX86.standardOutput = Pipe()
        procX86.standardError = Pipe()
        do {
            try procX86.run()
            procX86.waitUntilExit()
            if procX86.terminationStatus == 0 {
                return .x86_64
            }
        } catch {
            return .notBootable
        }

        return .notBootable
    }

    /// 从内置 ARM64 ISO 中提取内核与安装内存盘，并注入全自动无人值守安装脚本（无需手工点击向导即可自动分区、写入系统、配置 UEFI 引导并重启）
    public func prepareUnattendedInstallerAssets(isoPath: String, directory: URL) throws -> (kernelURL: URL, initrdURL: URL) {
        let kernelURL = directory.appendingPathComponent("fnos_installer_vmlinux")
        let initrdURL = directory.appendingPathComponent("fnos_installer_autoinstall_initrd.gz")
        let overlayDir = directory.appendingPathComponent("autoinstall_overlay_tmp")

        let fm = FileManager.default
        if fm.fileExists(atPath: kernelURL.path),
           fm.fileExists(atPath: initrdURL.path),
           let kAttr = try? fm.attributesOfItem(atPath: kernelURL.path),
           let iAttr = try? fm.attributesOfItem(atPath: initrdURL.path),
           (kAttr[.size] as? Int64 ?? 0) > 10_000_000,
           (iAttr[.size] as? Int64 ?? 0) > 10_000_000 {
            return (kernelURL, initrdURL)
        }

        try? fm.removeItem(at: overlayDir)
        let usrSbinDir = overlayDir.appendingPathComponent("usr/sbin")
        try fm.createDirectory(at: usrSbinDir, withIntermediateDirectories: true)

        let autoInstallScript = #"""
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ -f /tmp/.fnos_autoinstall_running ]; then
    exit 0
fi
touch /tmp/.fnos_autoinstall_running

log_msg() {
    echo "$1"
    if [ -c /dev/hvc0 ]; then
        echo "$1" > /dev/hvc0 2>/dev/null || true
    fi
}

log_msg "[BOOT] 正在加载 ARM64 虚拟存储与文件系统驱动模块..."

for mod in crc16 mbcache jbd2 ext4 isofs vfat fat nls_cp437 nls_iso8859-1 nls_utf8 nvme sr_mod cdrom sg virtio_blk virtio_scsi virtio_net ahci usb-storage uas; do
    modprobe "$mod" 2>/dev/null || true
done

mount -a 2>/dev/null || true
mkdir -p /dev/pts /mnt/cdrom /mnt/rootfs /boot/efi /usr/lib/grub
mount -t devpts devpts /dev/pts 2>/dev/null || true
sleep 2
mdev -s 2>/dev/null || true

log_msg "[ISO] 正在扫描并挂载内置飞牛 fnOS 安装镜像源..."
CD_DEV=""
for candidate in /dev/vdc /dev/vdb /dev/sr0 /dev/sda /dev/vdc1 /dev/vdb1; do
    if [ -b "$candidate" ]; then
        if mount -t iso9660 "$candidate" /mnt/cdrom 2>/dev/null || mount -r "$candidate" /mnt/cdrom 2>/dev/null; then
            if [ -f /mnt/cdrom/trimfs.tgz ]; then
                CD_DEV="$candidate"
                break
            fi
            umount /mnt/cdrom 2>/dev/null || true
        fi
    fi
done

if [ -z "$CD_DEV" ]; then
    log_msg "[ERROR] 未能找到包含 trimfs.tgz 的安装介质！"
    sleep 3
    poweroff -f
    exit 1
fi

log_msg "[ISO] 已成功挂载安装源 ($CD_DEV)，发现系统归档包 trimfs.tgz (1.87 GB)"

TARGET_DISK="/dev/vda"
if [ ! -b "$TARGET_DISK" ]; then
    log_msg "[ERROR] 未找到虚拟系统盘 /dev/vda！"
    sleep 3
    poweroff -f
    exit 1
fi

log_msg "[STORAGE] 正在对系统盘 $TARGET_DISK 创建 GPT 分区表 (EFI 100M + SYSTEM)..."
dd if=/dev/zero of="$TARGET_DISK" bs=1M count=2 conv=notrunc 2>/dev/null || true
parted --script "$TARGET_DISK" mklabel gpt mkpart BOOT 1M 100M mkpart SYSTEM 100M 100% set 1 esp on >/tmp/install.log 2>&1
sleep 1
mdev -s 2>/dev/null || true
sleep 1

log_msg "[STORAGE] 正在格式化 EFI 引导分区 (/dev/vda1) 与 EXT4 根分区 (/dev/vda2)..."
mkfs.vfat -F 32 /dev/vda1 >>/tmp/install.log 2>&1
mkfs.ext4 /dev/vda2 -F >>/tmp/install.log 2>&1

log_msg "[INSTALL] 正在将飞牛 fnOS 系统写入虚拟系统盘 (约需 20~35 秒)..."
mount -t ext4 /dev/vda2 /mnt/rootfs >>/tmp/install.log 2>&1

touch /tmp/.extracting_trimfs
(
    while [ -f /tmp/.extracting_trimfs ]; do
        sleep 3
        if [ -f /tmp/.extracting_trimfs ]; then
            USED_MB=$(df -m /mnt/rootfs 2>/dev/null | awk 'NR==2 {print $3}')
            if [ -n "$USED_MB" ]; then
                PCT=$((USED_MB * 100 / 4600))
                [ "$PCT" -gt 99 ] && PCT=99
                log_msg "[INSTALL] 正在写入飞牛 fnOS 系统文件: 已写入 ${USED_MB} MB (${PCT}%)..."
            fi
        fi
    done
) &
PROGRESS_PID=$!

tar xf /mnt/cdrom/trimfs.tgz -C /mnt/rootfs >>/tmp/install.log 2>&1
TAR_RET=$?
rm -f /tmp/.extracting_trimfs
kill "$PROGRESS_PID" 2>/dev/null || true

if [ "$TAR_RET" -ne 0 ]; then
    log_msg "[ERROR] 解压系统归档包失败 (code=$TAR_RET)"
    sleep 3
    poweroff -f
    exit 1
fi

log_msg "[INSTALL] 系统核心文件写入完成 (100%)，正在创建 Swap 交换文件与 /etc/fstab..."
mkdir -p /mnt/rootfs/dev /mnt/rootfs/run /mnt/rootfs/proc /mnt/rootfs/sys /mnt/rootfs/tmp /mnt/rootfs/boot/efi /mnt/rootfs/var/tmp

fallocate -l 1024M /mnt/rootfs/swapfile 2>/dev/null || dd if=/dev/zero of=/mnt/rootfs/swapfile bs=1M count=1024 >/dev/null 2>&1
chmod 0600 /mnt/rootfs/swapfile
mkswap /mnt/rootfs/swapfile >>/tmp/install.log 2>&1

BOOT_UUID=$(blkid -s UUID -o value /dev/vda1)
ROOT_UUID=$(blkid -s UUID -o value /dev/vda2)

cat > /mnt/rootfs/etc/fstab <<EOF
UUID=${ROOT_UUID} / ext4 errors=remount-ro 0 1
UUID=${BOOT_UUID} /boot/efi vfat umask=0077 0 1
/swapfile none swap sw 0 0
EOF

log_msg "[UEFI] 正在安装 ARM64 UEFI GRUB 引导程序并生成 initramfs..."
mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
mount -t vfat /dev/vda1 /boot/efi >>/tmp/install.log 2>&1
mount -t vfat /dev/vda1 /mnt/rootfs/boot/efi >>/tmp/install.log 2>&1
mount --bind /mnt/rootfs/usr/share /usr/share 2>/dev/null || true
mount --bind /mnt/rootfs/usr/lib/grub /usr/lib/grub 2>/dev/null || true

if [ -f /mnt/rootfs/etc/default/grub ]; then
    sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="FNOS"/' /mnt/rootfs/etc/default/grub
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="console=hvc0 console=tty0 quiet"/' /mnt/rootfs/etc/default/grub
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /mnt/rootfs/etc/default/grub
fi

/mnt/rootfs/usr/sbin/grub-install --target=arm64-efi --no-nvram --root-directory=/mnt/rootfs --efi-directory=/boot/efi --bootloader-id=debian /dev/vda >>/tmp/install.log 2>&1
mkdir -p /boot/efi/EFI/BOOT
cp -rf /boot/efi/EFI/debian/* /boot/efi/EFI/BOOT/ 2>/dev/null || true
if [ -f /boot/efi/EFI/BOOT/grubaa64.efi ]; then
    cp -f /boot/efi/EFI/BOOT/grubaa64.efi /boot/efi/EFI/BOOT/BOOTAA64.EFI
fi

mount --bind /dev /mnt/rootfs/dev
mount --bind /proc /mnt/rootfs/proc
mount --bind /sys /mnt/rootfs/sys

/trim-grub >>/tmp/install.log 2>&1 || chroot /mnt/rootfs /bin/sh -c "grub-mkconfig -o /boot/grub/grub.cfg && update-grub2 && mkdir -p /var/tmp && update-initramfs -u" >>/tmp/install.log 2>&1

log_msg "[READY] 正在同步磁盘块缓存 (sync)..."
sync
umount /mnt/rootfs/boot/efi 2>/dev/null || true
umount /boot/efi 2>/dev/null || true
umount /mnt/rootfs/sys 2>/dev/null || true
umount /mnt/rootfs/proc 2>/dev/null || true
umount /mnt/rootfs/dev 2>/dev/null || true
umount /mnt/rootfs 2>/dev/null || true
sync

log_msg "[FNOS_AUTO_INSTALL_DONE] 飞牛 fnOS 系统全自动安装完成！正在切换至正式系统运行..."
sleep 1
poweroff -f
"""#

        let startupScriptURL = usrSbinDir.appendingPathComponent("debian-installer-startup")
        let trimInstallURL = overlayDir.appendingPathComponent("trim-install")
        try autoInstallScript.write(to: startupScriptURL, atomically: true, encoding: .utf8)
        try autoInstallScript.write(to: trimInstallURL, atomically: true, encoding: .utf8)
        chmod(startupScriptURL.path, 0o755)
        chmod(trimInstallURL.path, 0o755)

        let shellCmd = """
        set -e
        /usr/bin/bsdtar -xOf "\(isoPath)" install.a64/vmlinuz | /usr/bin/gunzip -c > "\(kernelURL.path)"
        /usr/bin/bsdtar -xOf "\(isoPath)" install.a64/initrd.gz > "\(initrdURL.path)"
        cd "\(overlayDir.path)"
        printf "usr/sbin/debian-installer-startup\\ntrim-install\\n" | /usr/bin/cpio -o -H newc 2>/dev/null | /usr/bin/gzip -9 >> "\(initrdURL.path)"
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", shellCmd]
        try proc.run()
        proc.waitUntilExit()
        try? fm.removeItem(at: overlayDir)

        guard proc.terminationStatus == 0 else {
            throw StorageError.diskCreationFailed("提取无人值守安装内核与引导盘失败 (code=\(proc.terminationStatus))")
        }

        return (kernelURL, initrdURL)
    }

    public func findARMISO() -> String? {
        let candidates = [
            "/Volumes/Han/下载/fnos_Mainland-PE_arm_1.2.0302_armsr_2301_mac.iso",
            "/Volumes/Han/下载/fnos_Mainland-PE_arm_1.2.0302_armsr_2301.iso",
            "/Users/han/Downloads/fnos_Mainland-PE_arm_1.2.0302_armsr_2301.iso"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                if detectISOArchitecture(path: path) == .arm64 {
                    return path
                }
            }
        }
        return nil
    }

    public func getAllocatedFileSize(at path: String) -> (usedBytes: Int64, usedString: String) {
        var statBuf = stat()
        if stat(path, &statBuf) == 0 {
            let bytes = Int64(statBuf.st_blocks) * 512
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return (bytes, formatter.string(fromByteCount: bytes))
        }
        return (0, "0 B")
    }
}
