import Foundation

/// 卡片 payload 是服务端给的任意结构，客户端只负责原样回传
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析的 JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

enum CardKind: String, Codable {
    case createContact = "create_contact"
    case updateContact = "update_contact"
    case createMeeting = "create_meeting"

    /// 卡片上只显示这几个字，不显示任何字段
    var label: String {
        switch self {
        case .createContact: return "创建联系人"
        case .updateContact: return "更新联系人"
        case .createMeeting: return "创建会议"
        }
    }

    var icon: String {
        switch self {
        case .createContact: return "person.badge.plus"
        case .updateContact: return "arrow.triangle.2.circlepath"
        case .createMeeting: return "calendar.badge.plus"
        }
    }
}

struct ActionCard: Codable, Identifiable, Hashable {
    let id: String
    let kind: CardKind
    let reason: String?
    let payload: JSONValue
    /// 服务端记录的确认状态：刷新后已写入的卡片仍然折叠
    var confirmed: Bool?

    var fields: [String: JSONValue] { payload.objectValue ?? [:] }

    var contactName: String {
        switch kind {
        case .createContact: return fields["name"]?.stringValue ?? ""
        case .updateContact: return fields["targetName"]?.stringValue ?? ""
        case .createMeeting:
            let participants = fields["participants"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return participants.first ?? ""
        }
    }
}

/// 写系统（通讯录 / 日历）失败时给用户看的信息。
/// `needsSettings` 为真表示权限被用户关掉了：重试不会有变化，只能去设置里打开。
struct CardFailure: Equatable {
    let message: String
    let needsSettings: Bool
}
