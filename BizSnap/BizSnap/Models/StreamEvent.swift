import Foundation

/// 服务端 SSE 的 5 种帧，客户端只认 `data:` 行里的 `type`
enum StreamEvent {
    case started(messageId: String)
    case text(String)
    case card(ActionCard)
    case written([WrittenCard], contactName: String)
    case done(message: ChatMessage?, insight: String?, contactName: String, title: String?)
    case failed(String)
}

/// 一帧的原始结构：字段全可选，按 `type` 取用
struct RawStreamEvent: Decodable {
    let type: String
    let delta: String?
    let card: ActionCard?
    let message: ChatMessage?
    let written: [WrittenCard]?
    let contactName: String?
    let insight: String?
    let error: String?
    let messageId: String?
    /// 首轮结束后服务端生成的会话标题
    let title: String?

    func toEvent() -> StreamEvent? {
        switch type {
        case "start":
            return .started(messageId: messageId ?? "")
        case "text":
            guard let delta, !delta.isEmpty else { return nil }
            return .text(delta)
        case "card":
            return card.map { .card($0) }
        case "written":
            return .written(written ?? [], contactName: contactName ?? "")
        case "done":
            return .done(
                message: message,
                insight: insight,
                contactName: contactName ?? "",
                title: title
            )
        case "error":
            return .failed(error ?? "服务端错误")
        default:
            return nil
        }
    }
}
