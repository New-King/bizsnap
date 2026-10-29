import SwiftUI

enum Theme {
    // 近黑背景，三层递进
    static let background = Color(hex: 0x0E0F12)
    static let surface = Color(hex: 0x16181D)
    static let elevated = Color(hex: 0x1E2128)

    // 单一蓝色强调
    static let accent = Color(hex: 0x5B8CFF)
    static let accentSoft = Color(hex: 0x7AA2FF)

    static let textPrimary = Color(hex: 0xF2F3F5)
    static let textSecondary = Color(hex: 0xA0A6B0)
    static let textTertiary = Color(hex: 0x6B7280)

    static let green = Color(hex: 0x34C759)
    static let orange = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)

    static let radius: CGFloat = 16
    static let gap: CGFloat = 8

    static let accentGradient = LinearGradient(
        colors: [accentSoft, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// 半透明叠加 + 1px 细边，全站唯一的「玻璃」质感
    func glassCard(radius: CGFloat = Theme.radius, padding: CGFloat = 12, active: Bool = false) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.elevated.opacity(active ? 0.95 : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(active ? Theme.accent.opacity(0.9) : Color.white.opacity(0.08), lineWidth: active ? 1.2 : 1)
            )
    }
}

extension String {
    /// createdAt / updatedAt 是 ISO 8601，列表里只显示 HH:mm 或 MM-dd
    var shortTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: self)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: self)
        }
        guard let date else { return "" }
        let calendar = Calendar.current
        let pattern = calendar.isDateInToday(date) ? "HH:mm" : "MM-dd"
        let display = DateFormatter()
        display.dateFormat = pattern
        display.locale = Locale(identifier: "zh_CN")
        return display.string(from: date)
    }
}
