import SwiftUI
import UIKit

enum Theme {
    // 三层递进，跟随系统浅色/深色
    static let background = Color.adaptive(light: 0xF4F5F7, dark: 0x0E0F12)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x16181D)
    static let elevated = Color.adaptive(light: 0xFFFFFF, dark: 0x1E2128)

    // 单一蓝色强调
    static let accent = Color.adaptive(light: 0x3D6EF0, dark: 0x5B8CFF)
    static let accentSoft = Color.adaptive(light: 0x5B8CFF, dark: 0x7AA2FF)

    static let textPrimary = Color.adaptive(light: 0x111318, dark: 0xF2F3F5)
    static let textSecondary = Color.adaptive(light: 0x565E6C, dark: 0xA0A6B0)
    static let textTertiary = Color.adaptive(light: 0x8A91A0, dark: 0x6B7280)

    static let green = Color.adaptive(light: 0x1FA84E, dark: 0x34C759)
    static let orange = Color.adaptive(light: 0xE08600, dark: 0xFF9F0A)
    static let red = Color.adaptive(light: 0xE03127, dark: 0xFF453A)

    /// 1px 描边与分隔线：浅色下用黑、深色下用白，调用处再叠加透明度
    static let stroke = Color.adaptive(light: 0x000000, dark: 0xFFFFFF)

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

    /// 同一语义色给两套取值，由系统外观决定用哪套
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
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
                    .stroke(active ? Theme.accent.opacity(0.9) : Theme.stroke.opacity(0.08), lineWidth: active ? 1.2 : 1)
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
