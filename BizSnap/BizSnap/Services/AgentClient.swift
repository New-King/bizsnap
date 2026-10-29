import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 服务端唯一入口：会话、消息、确认
@MainActor
final class AgentClient: ObservableObject {
    private enum Keys {
        static let server = "bizsnap.serverURL"
    }

    static let defaultServer = "http://127.0.0.1:8787"

    @Published private(set) var baseURL: URL
    @Published private(set) var online = false

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let saved = UserDefaults.standard.string(forKey: Keys.server) ?? Self.defaultServer
        baseURL = URL(string: saved) ?? URL(string: Self.defaultServer)!
        let configuration = URLSessionConfiguration.default
        // agent 推理 + 工具调用可能要几十秒
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 200
        session = URLSession(configuration: configuration)
    }

    var serverText: String { baseURL.absoluteString }

    func updateServer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }
        baseURL = url
        UserDefaults.standard.set(trimmed, forKey: Keys.server)
        online = false
    }

    // MARK: - 基础

    private func perform(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError(message: "服务地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError(message: "网络异常")
            }
            if http.statusCode >= 400 {
                if let payload = try? decoder.decode([String: JSONValue].self, from: data),
                   let message = payload["error"]?.stringValue {
                    throw APIError(message: message)
                }
                throw APIError(message: "服务返回 \(http.statusCode)")
            }
            online = true
            return data
        } catch {
            online = false
            if let apiError = error as? APIError { throw apiError }
            throw APIError(message: "连不上服务：\(error.localizedDescription)")
        }
    }

    private func jsonBody(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    func checkHealth() async {
        struct Health: Codable { let ok: Bool }
        _ = try? await perform("/api/health").decode(Health.self, decoder: decoder)
    }

    // MARK: - 会话

    func listThreads() async throws -> [ThreadSummary] {
        try decoder.decode([ThreadSummary].self, from: await perform("/api/threads"))
    }

    func createThread() async throws -> String {
        struct Result: Codable { let threadId: String }
        let data = try await perform("/api/threads", method: "POST", body: jsonBody([:]))
        return try decoder.decode(Result.self, from: data).threadId
    }

    func renameThread(_ id: String, title: String) async throws {
        _ = try await perform("/api/threads/\(id)", method: "PATCH", body: jsonBody(["title": title]))
    }

    func deleteThread(_ id: String) async throws {
        _ = try await perform("/api/threads/\(id)", method: "DELETE")
    }

    // MARK: - 消息

    func messages(threadId: String) async throws -> [ChatMessage] {
        try decoder.decode([ChatMessage].self, from: await perform("/api/threads/\(threadId)/messages"))
    }

    func send(
        threadId: String,
        text: String,
        imageBase64: String?,
        snapshot: [ContactSnapshot]
    ) async throws -> ChatMessage {
        var body: [String: Any] = [:]
        if !text.isEmpty { body["text"] = text }
        if let imageBase64 { body["imageBase64"] = imageBase64 }
        if !snapshot.isEmpty {
            body["contactsSnapshot"] = snapshot.map { item -> [String: Any] in
                var dict: [String: Any] = ["name": item.name]
                if let company = item.company, !company.isEmpty { dict["company"] = company }
                if let position = item.position, !position.isEmpty { dict["position"] = position }
                if let phones = item.phones, !phones.isEmpty { dict["phones"] = phones }
                return dict
            }
        }

        let data = try await perform(
            "/api/threads/\(threadId)/messages",
            method: "POST",
            body: jsonBody(body)
        )
        return try decoder.decode(SendMessageResponse.self, from: data).message
    }

    // MARK: - 确认

    func confirm(threadId: String, cards: [ActionCard]) async throws -> ConfirmResponse {
        let payload = cards.map { card -> [String: Any] in
            var dict: [String: Any] = ["id": card.id, "kind": card.kind.rawValue]
            if let reason = card.reason { dict["reason"] = reason }
            dict["payload"] = card.payload.jsonObject
            return dict
        }
        let body = try JSONSerialization.data(withJSONObject: ["cards": payload])
        let data = try await perform("/api/threads/\(threadId)/confirm", method: "POST", body: body)
        return try decoder.decode(ConfirmResponse.self, from: data)
    }

    // MARK: - 演示数据

    @discardableResult
    func seedServerData() async throws -> SeedResult {
        try decoder.decode(SeedResult.self, from: await perform("/api/demo/seed", method: "POST"))
    }

    func resetServerData() async throws {
        _ = try await perform("/api/demo/reset", method: "POST")
    }
}

private extension JSONValue {
    /// 回传给服务端时把枚举还原成纯 JSON
    var jsonObject: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let value): return value.map(\.jsonObject)
        case .object(let value): return value.mapValues(\.jsonObject)
        }
    }
}

private extension Data {
    func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder) throws -> T {
        try decoder.decode(type, from: self)
    }
}
