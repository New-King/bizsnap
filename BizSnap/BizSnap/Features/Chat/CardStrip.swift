import SwiftUI

/// 一条窄卡：左边类型文案，右边圆形勾选框。不显示任何字段内容。
struct CardStrip: View {
    let card: ActionCard
    let selectable: Bool
    /// 流式过程中刚冒出来的卡：正常亮度但不可点
    var pending: Bool = false
    let isSelected: Bool
    /// 是否真的写进了系统通讯录 / 日历（服务端已确认 ≠ 系统已写入）
    var systemWritten: Bool = true
    let error: CardFailure?
    let onToggle: () -> Void
    let onRetry: () -> Void
    var onOpenSettings: (() -> Void)? = nil

    @State private var pulse = false

    private var folded: Bool { card.confirmed == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if folded {
                foldedRow
            } else {
                activeRow
            }

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(error.message)
                        .font(.system(size: 12))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    // 权限被关掉时重试必然失败，直接给出去设置的入口
                    if error.needsSettings, let onOpenSettings {
                        Button("去设置", action: onOpenSettings)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accentSoft)
                    }
                    Button("重试", action: onRetry)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentSoft)
                }
                .foregroundStyle(Theme.red)
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeRow: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: card.kind.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accentSoft : Theme.textSecondary)
                    .frame(width: 22)

                Text(card.kind.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 8)

                checkbox
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.elevated.opacity(isSelected ? 1 : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Theme.stroke.opacity(0.08), lineWidth: isSelected ? 1.4 : 1)
            )
            .scaleEffect(isSelected && pulse ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .opacity(selectable || pending ? 1 : 0.4)
        .onChange(of: isSelected) { _, value in
            guard value else {
                withAnimation(.easeOut(duration: 0.18)) { pulse = false }
                return
            }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { pulse = true }
        }
    }

    /// 折叠后的状态话术：只有真的写进系统才敢说「已写入」
    private var foldedText: String {
        switch (systemWritten, card.kind == .createMeeting) {
        case (true, true): return "已写入日历"
        case (true, false): return "已写入通讯录"
        case (false, true): return "已确认，未写入日历"
        case (false, false): return "已确认，未写入通讯录"
        }
    }

    private var foldedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: systemWritten ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(systemWritten ? Theme.green : Theme.orange)
            Text(foldedText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if systemWritten {
                Text(card.kind.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Button("写入", action: onRetry)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accentSoft)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var checkbox: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Theme.accent : Theme.stroke.opacity(0.22), lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
