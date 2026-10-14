import SwiftUI
import AppKit

@main
struct fnOSApp: App {
    @Environment(\.openWindow) private var openWindow

    init() {
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
        UpdateChecker.shared.checkInBackgroundOnLaunch()
    }

    var body: some Scene {
        WindowGroup {
            MiniCardView()
                .edgesIgnoringSafeArea(.all)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 390, height: 350)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 FnOS Manager") {
                    openWindow(id: "about-window")
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    openWindow(id: "settings-window")
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("查看运行日志…") {
                    openWindow(id: "log-window")
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            CommandGroup(replacing: .systemServices) {}
        }

        // 独立窗口 1: 关于 FnOS Manager
        Window("关于 FnOS Manager", id: "about-window") {
            AboutFnOSWindowView()
                .edgesIgnoringSafeArea(.all)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 380, height: 400)
        .windowResizability(.contentSize)

        // 独立窗口 2: 偏好设置 (点击左上角菜单「设置…」或界面齿轮均弹出此独立窗口)
        Window("偏好设置", id: "settings-window") {
            MiniSettingsSheetView(vmManager: VMManager.shared)
                .edgesIgnoringSafeArea(.all)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 445, height: 595)
        .windowResizability(.contentSize)

        // 独立窗口 3: 运行日志与引导画面查看器
        Window("运行日志", id: "log-window") {
            LogViewerWindowView(vmManager: VMManager.shared)
                .edgesIgnoringSafeArea(.all)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 490, height: 430)
        .windowResizability(.contentSize)
    }
}
