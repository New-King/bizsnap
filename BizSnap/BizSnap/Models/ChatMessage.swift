import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = MessageRole(rawValue: raw) ?? .assistant
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: String
    let role: MessageRole
    var text: String?
    var imageBase64: String?
    var cards: [ActionCard]?
    let createdAt: String

    var isUser: Bool { role == .user }
    var hasCards: Bool { !(cards ?? []).isEmpty }

    static func localAssistant(text: String) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            text: text,
            imageBase64: nil,
            cards: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func localUser(text: String, imageBase64: String?) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            role: .user,
            text: text.isEmpty ? nil : text,
            imageBase64: imageBase64,
            cards: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
