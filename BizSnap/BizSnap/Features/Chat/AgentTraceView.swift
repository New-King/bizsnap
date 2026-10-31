import SwiftUI

/// 一轮的链路：左边一条细线，右边按顺序排「思考」与「工具调用」。
/// 整体压得很淡、加一层很轻的阴影，再让它极缓地上下浮，读正文时不抢眼。
struct AgentTraceView: View {
    let steps: [TraceStep]

    @State private var floating = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 竖向细线：一眼看出这几行属于同一条链路
            Capsule()
                .fill(Theme.stroke.opacity(0.5))
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    row(step)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(0.72)
        // 朦胧感：不描边，只用一层大半径低透明度阴影把字从背景里托起来
        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 7, y: 2)
        .offset(y: floating ? -1.2 : 0.8)
        .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: floating)
        .animation(.easeOut(duration: 0.24), value: steps.count)
        .onAppear { floating = true }
        .onDisappear { floating = false }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("模型处理过程")
    }

    @ViewBuilder
    private func row(_ step: TraceStep) -> some View {
        switch step {
        case .reasoning(let text):
            Text(text)
                .font(.system(size: 11.5))
                .italic()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(text) // 整段替换时不复用旧行的动画状态

        case .tool(let tool):
            HStack(spacing: 5) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 12)
                Text(tool.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if let detail = tool.detail, !detail.isEmpty {
                    Text("· \(detail)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                statusMark(tool)
            }
            .id(tool.id)
        }
    }

    @ViewBuilder
    private func statusMark(_ tool: ToolTrace) -> some View {
        if tool.isRunning {
            Circle()
                .stroke(Theme.textTertiary.opacity(0.8), lineWidth: 1.2)
                .frame(width: 6, height: 6)
        } else if tool.isError {
            Image(systemName: "exclamationmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.textTertiary.opacity(0.9))
        }
    }
}
