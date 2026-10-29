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
        return start
    }
}
