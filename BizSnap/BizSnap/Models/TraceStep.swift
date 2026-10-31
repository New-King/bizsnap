import Foundation

/// 一次工具调用。id 与模型侧 toolCallId 对齐，结果回来时按 id 就地更新状态
struct ToolTrace: Codable, Hashable, Identifiable {
    let id: String
    let tool: String
    /// 中文短标签，服务端已经翻好，如「查联系人」
    let label: String
    /// 关键入参，如人名、会议标题
    let detail: String?
    /// running / ok / error
    var status: String

    var isRunning: Bool { status == "running" }
    var isError: Bool { status == "error" }

    /// 链路前面的小图标：工具还没报结果时也一样显示，先让人看到「在做什么」
    var symbol: String {
        switch tool {
        case "search_contact": return "magnifyingglass"
        case "search_interactions": return "text.magnifyingglass"
        case "get_contact_history": return "clock.arrow.circlepath"
        case "create_contact": return "person.badge.plus"
        case "update_contact": return "pencil.line"
        case "create_meeting": return "calendar.badge.plus"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// 一轮里模型做过的事：一段思考，或一次工具调用
enum TraceStep: Codable, Hashable {
    case reasoning(String)
    case tool(ToolTrace)

    private enum CodingKeys: String, CodingKey {
        case kind, text, id, tool, label, detail, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        if kind == "reasoning" {
            self = .reasoning(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
            return
        }
        self = .tool(
            ToolTrace(
                id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
                tool: try container.decodeIfPresent(String.self, forKey: .tool) ?? "",
                label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
                detail: try container.decodeIfPresent(String.self, forKey: .detail),
                status: try container.decodeIfPresent(String.self, forKey: .status) ?? "ok"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reasoning(let text):
            try container.encode("reasoning", forKey: .kind)
            try container.encode(text, forKey: .text)
        case .tool(let tool):
            try container.encode("tool", forKey: .kind)
            try container.encode(tool.id, forKey: .id)
            try container.encode(tool.tool, forKey: .tool)
            try container.encode(tool.label, forKey: .label)
            try container.encodeIfPresent(tool.detail, forKey: .detail)
            try container.encode(tool.status, forKey: .status)
        }
    }
}
