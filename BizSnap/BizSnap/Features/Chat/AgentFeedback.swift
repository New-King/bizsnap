import Foundation

/// 流里每一种结果都从这里取一句话。
///
/// 规则见 `docs/plan.md`「十二、iOS 客户端 · 反馈规则」：任何一次交互都要有一句话落到消息流里。
/// 只改顶部状态条、只把卡片标红都不算反馈——用户会以为刚才那一下没生效。
/// 新增失败路径时先在这里加文案，不要在各处 if 里现拼中文。
enum AgentFeedback {
    /// 这条流是被什么触发的，决定同一句文案落到哪个语境
    enum Context {
        /// 用户发了一条消息
        case turn
        /// 用户点了「确认选中」
        case confirm
    }

    /// 模型侧返回 failed
    static func incomplete(_ context: Context, reason: String?) -> String {
        let detail = reason.map { "：\($0)" } ?? ""
        switch context {
        case .turn:
            return "这次没跑完\(detail)。点下面的重试再来一次，或者换个说法。"
        case .confirm:
            return "确认没走完\(detail)。卡片还在，再点一次确认就行。"
        }
    }

    /// 连接层就断了，模型那边根本没返回
    static func disconnected(_ context: Context, reason: String) -> String {
        switch context {
        case .turn:
            return "这次没连上服务：\(reason)。确认服务起着，再点下面的重试。"
        case .confirm:
            return "确认没连上服务：\(reason)。卡片还在，再点一次确认就行。"
        }
    }

    /// 写系统通讯录 / 日历失败：卡片上只会标红，为什么没成得说清
    static func systemWriteFailed(_ failures: [(label: String, who: String, reason: String)]) -> String {
        let detail = failures
            .map { item in
                let who = item.who.isEmpty ? "" : "（\(item.who)）"
                return "\(item.label)\(who)：\(item.reason)"
            }
            .joined(separator: "；")
        return "写进系统的时候没成——\(detail)。权限开了就点卡片上的重试；被关掉的先去设置里打开。"
    }

    /// 单张卡片重试后仍然失败
    static func retryStillFailed(label: String, who: String, reason: String) -> String {
        let name = who.isEmpty ? "" : "（\(who)）"
        return "又试了一次，还是没成——\(label)\(name)：\(reason)。"
    }

    /// 选了图却压不出来
    static let imageUnreadable = "这张图没能读出来，换一张再试。"
}
