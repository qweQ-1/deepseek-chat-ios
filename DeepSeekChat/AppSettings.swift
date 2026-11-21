import Foundation

/// 本机设置：API Key 与模型。
///
/// 页面自身也会把 API Key 存进 localStorage（键 `chat-demo:api-key`），
/// 首次启动时由原生设置页把值注入进去，之后在页面里修改也会同步生效。
enum AppSettings {

    static let fallbackModels = ["deepseek-flash", "deepseek-v4-pro"]
    static let defaultModel = "deepseek-flash"

    private enum Key {
        static let apiKey = "deepseekchat.apiKey"
        static let model = "deepseekchat.model"
        static let models = "deepseekchat.models"
        /// 是否已经走过一次引导，避免每次启动都弹原生设置
        static let onboarded = "deepseekchat.onboarded"
    }

    static var apiKey: String? {
        get {
            guard let value = UserDefaults.standard.string(forKey: Key.apiKey),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.apiKey)
        }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: Key.model) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: Key.model) }
    }

    /// 上次从 /models 拉到的可用模型列表
    static var knownModels: [String] {
        get {
            let value = UserDefaults.standard.stringArray(forKey: Key.models) ?? []
            return value.isEmpty ? fallbackModels : value
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.models) }
    }

    static var onboarded: Bool {
        get { UserDefaults.standard.bool(forKey: Key.onboarded) }
        set { UserDefaults.standard.set(newValue, forKey: Key.onboarded) }
    }

    static var isConfigured: Bool { apiKey != nil }
}
