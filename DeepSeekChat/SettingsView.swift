import SwiftUI
import UIKit

/// 原生设置：填 API Key、选模型。
/// 页面本身也有设置面板，这里只是为了「第一次打开就能用」，以及随时能换模型。
@MainActor
struct SettingsView: View {

    private enum Status: Equatable {
        case idle
        case working
        case ok(String)
        case failed(String)
    }

    @State private var apiKey: String
    @State private var model: String
    @State private var models: [String]
    @State private var status: Status = .idle
    @FocusState private var keyFocused: Bool

    private let firstRun: Bool
    private let onSave: (String, String) -> Void
    private let onCancel: () -> Void
    private let onModelsLoaded: ([String]) -> Void

    private let accent = Color(red: 0.30, green: 0.42, blue: 0.99)

    init(apiKey: String,
         model: String,
         models: [String],
         firstRun: Bool,
         onSave: @escaping (String, String) -> Void,
         onCancel: @escaping () -> Void,
         onModelsLoaded: @escaping ([String]) -> Void) {
        _apiKey = State(initialValue: apiKey)
        _model = State(initialValue: model)
        _models = State(initialValue: models.isEmpty ? AppSettings.fallbackModels : models)
        self.firstRun = firstRun
        self.onSave = onSave
        self.onCancel = onCancel
        self.onModelsLoaded = onModelsLoaded
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if firstRun {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("欢迎使用 DeepSeek")
                                .font(.title3.weight(.semibold))
                            Text("界面来自 DeepSeek 官方开源的 chat-demo，聊天请求由本机直接发往 api.deepseek.com。填好 API Key 就能开始。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    SecureField("sk-...", text: $apiKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($keyFocused)
                        .font(.system(.body, design: .monospaced))
                        .submitLabel(.done)

                    HStack {
                        Button("粘贴") {
                            if let text = UIPasteboard.general.string {
                                apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Button(status == .working ? "验证中…" : "验证并读取模型") {
                            Task { await loadModels() }
                        }
                        .buttonStyle(.borderless)
                        .disabled(status == .working || trimmedKey.isEmpty)
                    }
                    .font(.subheadline)
                } header: {
                    Text("API Key")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        switch status {
                        case .idle:
                            Text("Key 只保存在本机，不会上传到任何第三方。")
                        case .working:
                            Text("正在请求 api.deepseek.com/models …")
                        case .ok(let message):
                            Label(message, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed(let message):
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Link("获取 API Key → platform.deepseek.com",
                             destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                            .font(.footnote)
                    }
                }

                Section {
                    Picker("模型", selection: $model) {
                        ForEach(models, id: \.self) { item in
                            Text(displayName(item)).tag(item)
                        }
                        if !models.contains(model) {
                            Text(displayName(model)).tag(model)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("模型")
                } footer: {
                    Text("deepseek-flash 支持深度思考与图片输入；deepseek-v4-pro 文本更强、不支持图片。")
                }

                Section {
                    Button {
                        keyFocused = false
                        onSave(trimmedKey, model)
                    } label: {
                        HStack {
                            Spacer()
                            Text(firstRun ? "开始使用" : "保存并重新加载")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(trimmedKey.isEmpty)

                    if !firstRun {
                        Button(role: .cancel) {
                            onCancel()
                        } label: {
                            HStack {
                                Spacer()
                                Text("取消")
                                Spacer()
                            }
                        }
                    }
                }

                Section {
                    Text("之后可在桌面长按 App 图标 →「DeepSeek 设置」随时修改。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(versionLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(firstRun ? "连接 DeepSeek" : "DeepSeek 设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(accent)
    }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "版本 \(version) (\(build)) · 前端基于 deepseek-ai/chat-demo（MIT）"
    }

    private func displayName(_ id: String) -> String {
        switch id {
        case "deepseek-flash": return "deepseek-flash（推荐）"
        case "deepseek-v4-pro": return "deepseek-v4-pro（更强文本）"
        default: return id
        }
    }

    private func loadModels() async {
        status = .working
        do {
            let fetched = try await DeepSeekAPI.listModels(apiKey: trimmedKey)
            models = fetched
            if !fetched.contains(model) {
                model = fetched.contains(AppSettings.defaultModel) ? AppSettings.defaultModel : fetched[0]
            }
            onModelsLoaded(fetched)
            status = .ok("Key 有效，可用模型 \(fetched.count) 个")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
