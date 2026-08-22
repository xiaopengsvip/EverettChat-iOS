import SwiftUI

/// 2026 AI-Native 设计系统（深色 · 单一蓝紫 Accent · Liquid Glass）
enum Theme {
    // 背景层次
    static let bg = Color(hex: 0x08090D)
    static let bgAlt = Color(hex: 0x0B0C11)
    static let surface = Color(hex: 0x11131A)
    static let surfaceHigh = Color(hex: 0x151722)
    static let surfaceAlt = Color(hex: 0x1A1C27)
    static let elevated = Color(hex: 0x1E202C)
    static let glass = Color(hex: 0xD90B0C11)

    // Accent（仅强调）
    static let primary = Color(hex: 0x8B5CF6)
    static let secondary = Color(hex: 0x7C6CFF)
    static let primaryDim = Color(hex: 0x3B2A6E)

    // 文字层级
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0xA1A4B3)
    static let textTertiary = Color(hex: 0x6E7280)

    // 功能色
    static let success = Color(hex: 0x32D583)
    static let error = Color(hex: 0xFF5C6C)
    static let warning = Color(hex: 0xF5B84B)
    static let info = Color(hex: 0x6D9DF5)

    // 描边
    static let outline = Color(hex: 0x14FFFFFF)
    static let outlineStrong = Color(hex: 0x26FFFFFF)

    // 气泡
    static let bubbleMine = Color(hex: 0x7C5CF0)
    static let bubbleAi = Color(hex: 0x14161F)
    static let bubblePeer = Color(hex: 0x1A1C27)
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// 间距 Token
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

/// 圆角 Token
enum Radius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 18
    static let floating: CGFloat = 24
}
