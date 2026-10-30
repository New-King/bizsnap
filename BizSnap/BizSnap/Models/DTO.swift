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

    /// 还没落库的新会话：本地占位，用户发出第一条消息时才向服务端创建
    var isDraft: Bool { id.hasPrefix("draft-") }

    static func draft() -> ThreadSummary {
        ThreadSummary(id: "draft-\(UUID().uuidString)", title: "", contactName: "", lastMessage: "", updatedAt: "")
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

struct WrittenCard: Codable, Hashable {
    let cardId: String
    let kind: String
    let contactName: String
    let background: String
    let ok: Bool
    let error: String?
}

/// 清空服务端后返回的名单：客户端拿它把写进系统通讯录 / 日历的条目也删掉
struct ResetResult: Codable {
    let createdNames: [String]
    let meetingTitles: [String]

    static let empty = ResetResult(createdNames: [], meetingTitles: [])
}
