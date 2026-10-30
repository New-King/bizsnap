import EventKit
import Foundation

/// 系统权限被用户关掉：只能去设置里打开，重试不会有变化
enum SystemAccessError: LocalizedError {
    case contactsDenied
    case calendarDenied

    var errorDescription: String? {
        switch self {
        case .contactsDenied: return "通讯录权限已关闭，需在设置里打开"
        case .calendarDenied: return "日历权限已关闭，需在设置里打开"
        }
    }
}

/// 真的写进系统的那几张卡。服务端的 confirmed 只代表业务库已落库，
/// 不等于系统写成功（可能没权限、可能在写之前退了 App），所以本地单独记一份。
enum SystemWriteLog {
    private static let key = "systemWrittenCardIds"

    static var ids: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func contains(_ cardId: String) -> Bool {
        ids.contains(cardId)
    }

    static func mark(_ cardId: String) {
        var all = ids
        all.insert(cardId)
        UserDefaults.standard.set(Array(all), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// 服务端已落库后，逐张卡写系统通讯录 / 日历。单张失败不影响其它卡。
@MainActor
enum CardExecutor {
    static func execute(_ card: ActionCard) async throws -> String {
        let result = try await perform(card)
        SystemWriteLog.mark(card.id)
        return result
    }

    private static func perform(_ card: ActionCard) async throws -> String {
        switch card.kind {
        case .createContact:
            let fields = card.fields
            guard let name = fields["name"]?.stringValue, !name.isEmpty else {
                throw APIError(message: "卡片缺少姓名")
            }
            try await ensureContactsAccess()
            return try ContactsService.shared.upsert(
                name: name,
                phone: fields["phone"]?.stringValue,
                email: fields["email"]?.stringValue,
                company: fields["company"]?.stringValue,
                position: fields["position"]?.stringValue
            )

        case .updateContact:
            let fields = card.fields
            guard let name = fields["targetName"]?.stringValue, !name.isEmpty else {
                throw APIError(message: "卡片缺少目标联系人")
            }
            let changes = fields["changes"]?.objectValue ?? [:]
            try await ensureContactsAccess()
            return try ContactsService.shared.upsert(
                name: name,
                phone: changes["phone"]?.stringValue,
                email: changes["email"]?.stringValue,
                company: changes["company"]?.stringValue,
                position: changes["position"]?.stringValue
            )

        case .createMeeting:
            let fields = card.fields
            guard let title = fields["title"]?.stringValue,
                  let start = fields["startTime"]?.stringValue,
                  let end = fields["endTime"]?.stringValue else {
                throw APIError(message: "卡片缺少会议时间")
            }
            guard await CalendarService.shared.requestAccess() else {
                throw SystemAccessError.calendarDenied
            }
            let participants = fields["participants"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let remark = fields["remark"]?.stringValue
            var notes: [String] = []
            if let remark, !remark.isEmpty { notes.append(remark) }
            if !participants.isEmpty { notes.append("参与人：" + participants.joined(separator: "、")) }

            let date = try CalendarService.shared.createEvent(
                title: title,
                startTime: start,
                endTime: end,
                location: fields["location"]?.stringValue,
                notes: notes.joined(separator: "\n")
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "M 月 d 日 HH:mm"
            formatter.locale = Locale(identifier: "zh_CN")
            return "已写入日历：\(formatter.string(from: date))"
        }
    }

    /// 还没问过就当场弹系统授权框；已经被拒才抛错，交给界面引导去设置
    private static func ensureContactsAccess() async throws {
        switch ContactsService.shared.status {
        case .authorized:
            return
        case .notDetermined:
            guard await ContactsService.shared.requestAccess() else {
                throw SystemAccessError.contactsDenied
            }
        default:
            throw SystemAccessError.contactsDenied
        }
    }

    /// 这张卡现在点重试有没有意义：权限被拒时只能去设置，重试不会变
    static func needsSettings(for card: ActionCard) -> Bool {
        switch card.kind {
        case .createContact, .updateContact:
            switch ContactsService.shared.status {
            case .denied, .restricted: return true
            default: return false
            }
        case .createMeeting:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .denied, .restricted: return true
            default: return false
            }
        }
    }
}
