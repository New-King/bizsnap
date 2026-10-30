import EventKit
import Foundation

enum CalendarError: LocalizedError {
    case noAccess
    case badTime(String)
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .noAccess: return "没有日历权限，去系统设置里打开后重试"
        case .badTime(let value): return "时间格式不对：\(value)"
        case .noCalendar: return "没有可写入的默认日历"
        }
    }
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    /// 本应用写进系统日历的事件，清空时按 identifier 删
    private static let createdKey = "createdEventIdentifiers"

    private var createdIdentifiers: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.createdKey) ?? [])
    }

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            }
            return try await store.requestAccess(to: .event)
        } catch {
            return false
        }
    }

    /// 写进系统日历；时间必须是带偏移的 ISO 8601，解析不了就让用户重来
    @discardableResult
    func createEvent(
        title: String,
        startTime: String,
        endTime: String,
        location: String?,
        notes: String?
    ) throws -> Date {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess
            || EKEventStore.authorizationStatus(for: .event) == .writeOnly
            || EKEventStore.authorizationStatus(for: .event) == .authorized
        else {
            throw CalendarError.noAccess
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let start = formatter.date(from: startTime) else {
            throw CalendarError.badTime(startTime)
        }
        guard let end = formatter.date(from: endTime), end > start else {
            throw CalendarError.badTime(endTime)
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarError.noCalendar
        }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        if let location, !location.isEmpty { event.location = location }
        if let notes, !notes.isEmpty { event.notes = notes }

        try store.save(event, span: .thisEvent, commit: true)
        if let id = event.eventIdentifier {
            var all = createdIdentifiers
            all.insert(id)
            UserDefaults.standard.set(Array(all), forKey: Self.createdKey)
        }
        return start
    }

    /// 删掉本应用写进日历的事件
    /// - Parameter titles: 服务端记录的会议标题，用于兜底没记下 identifier 的旧数据
    @discardableResult
    func deleteCreated(titles: [String] = []) -> Int {
        var handled = Set<String>()
        var removed = 0

        for id in createdIdentifiers {
            guard let event = store.event(withIdentifier: id) else { continue }
            do {
                try store.remove(event, span: .thisEvent, commit: false)
                handled.insert(id)
                removed += 1
            } catch {
                continue
            }
        }

        // 兜底：按标题在前后两年里找，只删标题完全一致的
        if !titles.isEmpty {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .year, value: -2, to: Date()) ?? Date()
            let end = calendar.date(byAdding: .year, value: 2, to: Date()) ?? Date()
            let wanted = Set(titles)
            let matches = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            for event in matches where wanted.contains(event.title) {
                guard let id = event.eventIdentifier, !handled.contains(id) else { continue }
                do {
                    try store.remove(event, span: .thisEvent, commit: false)
                    handled.insert(id)
                    removed += 1
                } catch {
                    continue
                }
            }
        }

        if removed > 0 { try? store.commit() }
        UserDefaults.standard.removeObject(forKey: Self.createdKey)
        return removed
    }
}
