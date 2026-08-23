import SwiftUI

enum AppTheme {
    struct Current {
        var isDark: Bool { AppTheme.isDark }
    }

    static var current: Current { Current() }
    static var isDark: Bool = false
    static var mode: String = "system"

    static func apply(_ mode: String, systemDark: Bool) {
        let normalizedMode = ["light", "dark", "system"].contains(mode) ? mode : "system"
        self.mode = normalizedMode

        switch normalizedMode {
        case "light":
            isDark = false
        case "dark":
            isDark = true
        default:
            isDark = systemDark
        }
    }
}

/// EVO 2026 Design System: Pearl White / Deep Black
enum Theme {
    // Text — 系统语义色（自动适配深浅色与 Dynamic Type）
    static var textPrimary: Color { .primary }
    static var textSecondary: Color { .secondary }
    static var textTertiary: Color { Color(UIColor.tertiaryLabel) }

    // Background layers — 系统分组背景（原生质感）
    static var bg: Color { Color(.systemGroupedBackground) }
    static var bgAlt: Color { Color(.secondarySystemGroupedBackground) }
    static var surface: Color { AppTheme.current.isDark ? Color(hex: 0x111114) : Color(hex: 0xFFFFFF) }
    static var surfaceHigh: Color { AppTheme.current.isDark ? Color(hex: 0x16161A) : Color(hex: 0xFAFAF9) }
    static var surfaceAlt: Color { AppTheme.current.isDark ? Color(hex: 0x1B1B20) : Color(hex: 0xF4F4F2) }
    static var elevated: Color { AppTheme.current.isDark ? Color(hex: 0x1B1B20) : Color(hex: 0xFFFFFF) }
    static var glass: Color {
        AppTheme.current.isDark
            ? Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255, opacity: 0.72)
            : Color(red: 1, green: 1, blue: 1, opacity: 0.72)
    }

    // Accent
    static var primary: Color { AppTheme.current.isDark ? Color(hex: 0x8B72FF) : Color(hex: 0x7657FF) }
    static var secondary: Color { AppTheme.current.isDark ? Color(hex: 0x7C6CFF) : Color(hex: 0x9B78FF) }
    static var primaryDim: Color { AppTheme.current.isDark ? Color(hex: 0x2A2150) : Color(hex: 0xE9E4FF) }

    static var success: Color { AppTheme.current.isDark ? Color(hex: 0x32D583) : Color(hex: 0x34C759) }
    static var error: Color { AppTheme.current.isDark ? Color(hex: 0xFF5C6C) : Color(hex: 0xFF3B30) }
    static var warning: Color { AppTheme.current.isDark ? Color(hex: 0xF5B84B) : Color(hex: 0xFF9F0A) }
    static var info: Color { AppTheme.current.isDark ? Color(hex: 0x6D9DF5) : Color(hex: 0x007AFF) }

    // Outlines
    static var outline: Color { AppTheme.current.isDark ? Color(hex: 0x1AFFFFFF) : Color(hex: 0x14000000) }
    static var outlineStrong: Color { AppTheme.current.isDark ? Color(hex: 0x26FFFFFF) : Color(hex: 0x26000000) }

    // Bubbles
    static var bubbleMine: Color { AppTheme.current.isDark ? Color(hex: 0x7C5CF0) : Color(hex: 0x7657FF) }
    static var bubbleAi: Color { AppTheme.current.isDark ? Color(hex: 0x16161C) : Color(hex: 0xF0EFF7) }
    static var bubblePeer: Color { AppTheme.current.isDark ? Color(hex: 0x1B1B20) : Color(hex: 0xE8E8EC) }
}

extension Color {
    init(hex: UInt32) {
        let hasAlpha = hex > 0xFFFFFF
        let a = hasAlpha ? Double((hex >> 24) & 0xFF) / 255.0 : 1.0
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: a)
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
