import Foundation

/// 会话列表行
struct ThreadSummary: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var contactName: String
    var lastMessage: String
    var updatedAt: String

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !contactName.isEmpty { return contactName }
        return "新会话"
    }

    var avatarText: String {
        String(displayTitle.prefix(1))
    }
}

/// 首次进入或通讯录变更后上传，最多 200 条
struct ContactSnapshot: Codable, Hashable {
    var name: String
    var company: String?
    var position: String?
    var phones: [String]?

    init(name: String, company: String?, position: String?, phones: [String]?) {
        self.name = name
        self.company = company
        self.position = position
        self.phones = phones
    }
}

struct SendMessageRequest: Codable {
    var text: String?
    var imageBase64: String?
    var contactsSnapshot: [ContactSnapshot]?
}

struct SendMessageResponse: Codable {
    let message: ChatMessage
}

struct WrittenCard: Codable, Hashable {
    let cardId: String
    let kind: String
    let contactName: String
    let background: String
    let ok: Bool
    let error: String?
}

struct ConfirmResponse: Codable {
    let ok: Bool
    let written: [WrittenCard]
    let insight: String
    let contactName: String
}

struct SeedResult: Codable {
    let contacts: Int
    let interactions: Int
}
