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
        /// 外观（明暗 / 主题色 / 字号），JSON 存 UserDefaults
        static let theme = "deepseekchat.theme"
        /// 首启时是否已经弹过「导入官网记录」的提示
        static let importPromptShown = "deepseekchat.importPromptShown"
    }

    /// 首启导入引导只弹一次
    static var importPromptShown: Bool {
        get { UserDefaults.standard.bool(forKey: Key.importPromptShown) }
        set { UserDefaults.standard.set(newValue, forKey: Key.importPromptShown) }
    }

    static var theme: AppTheme {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.theme),
                  let value = try? JSONDecoder().decode(AppTheme.self, from: data) else {
                return .default
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Key.theme)
            }
        }
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
