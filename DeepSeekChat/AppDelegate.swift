import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    /// 冷启动时通过桌面快捷菜单进入设置页，页面还没准备好，先记下来
    static var pendingOpenSettings = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        registerShortcutItems()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "com.qweq-1.deepseekchat.settings" {
            AppDelegate.pendingOpenSettings = true
            NotificationCenter.default.post(name: .deepSeekOpenSettings, object: nil)
        }
        completionHandler(true)
    }

    private func registerShortcutItems() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: "com.qweq-1.deepseekchat.settings",
                localizedTitle: "DeepSeek 设置",
                localizedSubtitle: "API Key 与模型",
                icon: UIApplicationShortcutIcon(systemImageName: "slider.horizontal.3")),
        ]
    }
}
