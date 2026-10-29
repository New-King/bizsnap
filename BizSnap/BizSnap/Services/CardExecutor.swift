import Foundation

/// 服务端已落库后，逐张卡写系统通讯录 / 日历。单张失败不影响其它卡。
@MainActor
enum CardExecutor {
    static func execute(_ card: ActionCard) async throws -> String {
        switch card.kind {
        case .createContact:
            let fields = card.fields
            guard let name = fields["name"]?.stringValue, !name.isEmpty else {
                throw APIError(message: "卡片缺少姓名")
            }
            try ensureContactsAccess()
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
            try ensureContactsAccess()
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
                throw CalendarError.noAccess
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

    private static func ensureContactsAccess() throws {
        switch ContactsService.shared.status {
        case .authorized:
            return
        case .notDetermined:
            throw APIError(message: "还没有通讯录权限，先在设置页授权")
        default:
            throw APIError(message: "通讯录权限被拒绝，去系统设置里打开")
        }
    }
}
