import Foundation

/// 服务端 SSE 的各种帧，客户端只认 `data:` 行里的 `type`
enum StreamEvent {
    case started(messageId: String)
    /// 模型思考的增量：界面往后接，不要整段重发
    case reasoning(String)
    /// 工具调用的一步：新调用或结果回填，按 id 就地对齐
    case tool(ToolTrace)
    case text(String)
    case card(ActionCard)
    case written([WrittenCard], contactName: String)
    case done(message: ChatMessage?, insight: String?, contactName: String, title: String?)
    /// done 之后单独补的会话标题：标题要再调一次模型，不挡在这条流前面
    case title(String)
    case failed(String)
}

/// 一帧的原始结构：字段全可选，按 `type` 取用
struct RawStreamEvent: Decodable {
    let type: String
    let delta: String?
    /// 工具调用的一步（type == "tool"）
    let step: ToolTrace?
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
        case "reasoning":
            guard let delta, !delta.isEmpty else { return nil }
            return .reasoning(delta)
        case "tool":
            return step.map { .tool($0) }
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
        case "title":
            guard let title, !title.isEmpty else { return nil }
            return .title(title)
        case "error":
            return .failed(error ?? "服务端错误")
        default:
            return nil
        }
    }
}
