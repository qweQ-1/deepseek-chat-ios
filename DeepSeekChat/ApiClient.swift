import Foundation

/// DeepSeek 开放平台的最小原生客户端，只用于「校验 API Key + 拉模型列表」。
/// 聊天请求全部由页面里的官方前端自己发出，原生层不参与。
enum DeepSeekAPI {

    static let origin = URL(string: "https://api.deepseek.com")!

    struct ModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]?
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let message: String? }
        let error: Body?
    }

    enum APIError: LocalizedError {
        case badKey
        case server(String, Int)
        case malformed
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .badKey: return "API Key 无效或已失效"
            case .server(let message, let status): return "\(message)（HTTP \(status)）"
            case .malformed: return "服务器返回了无法解析的内容"
            case .transport(let message): return message
            }
        }
    }

    /// GET /models —— 不产生费用，同时验证 Key 是否可用
    static func listModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: origin.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.malformed
        }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
            if http.statusCode == 401 || http.statusCode == 403 {
                throw APIError.server(message ?? "API Key 无效", http.statusCode)
            }
            throw APIError.server(message ?? "请求失败", http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            throw APIError.malformed
        }
        let ids = (decoded.data ?? []).map(\.id).filter { !$0.isEmpty }
        return ids.isEmpty ? AppSettings.fallbackModels : ids
    }
}
