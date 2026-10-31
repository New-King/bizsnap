import SwiftUI
import UIKit

enum Theme {
    // 深色走中性黑，靠 1%–3% 的明度差分层，不用纯黑也不用蓝灰
    static let background = Color.adaptive(light: 0xF5F5F3, dark: 0x0B0B0A)
    static let surface = Color.adaptive(light: 0xFCFCFB, dark: 0x151515)
    static let elevated = Color.adaptive(light: 0xFFFFFF, dark: 0x1A1A19)
    /// 最内层：输入框、选中态的底
    static let inset = Color.adaptive(light: 0xF0F0EE, dark: 0x20201E)

    // 单一蓝色强调
    static let accent = Color.adaptive(light: 0x3D6EF0, dark: 0x5B8CFF)
    static let accentSoft = Color.adaptive(light: 0x5B8CFF, dark: 0x7AA2FF)

    // 深色下正文不上纯白：白字在暗底上会「发胖」
    static let textPrimary = Color.adaptive(light: 0x111318, dark: 0xE9EBEF)
    static let textSecondary = Color.adaptive(light: 0x565E6C, dark: 0x9BA1AB)
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
