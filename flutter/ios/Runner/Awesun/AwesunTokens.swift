import SwiftUI
import UIKit

// MARK: - Session design tokens

extension Color {
    init(awesun argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum AwesunPalette {
    static let padFill = Color(awesun: 0xFF141B28)
    static let padFillPressed = Color(awesun: 0xFF222D40)
    static let padStroke = Color(awesun: 0xFF334158)
    static let dpadFill = Color(awesun: 0xFF1C2638)
    static let mint = Color(awesun: 0xFF60A5FA)
    static let hudFill = Color(awesun: 0xE60F1522)
    static let hudLabel = Color(awesun: 0xFF94A3B8)
    static let hudValue = Color(awesun: 0xFFFFFFFF)
    static let hudGreen = Color(awesun: 0xFF34D399)
    static let pairFill = Color(awesun: 0xFF141B28)
    static let pairStroke = Color(awesun: 0xFF334158)
    static let glyph = Color(awesun: 0xFFF1F5FA)

    static let brandBlue = Color(awesun: 0xFF3B82F6)
    static let activeBlue = Color(awesun: 0xE03B82F6)
    static let activeIce = Color(awesun: 0xFF60A5FA)
    static let brandRed = Color(awesun: 0xFFEF4444)
    static let kbBackground = Color(awesun: 0xF0111827)
    static let kbKey = Color(awesun: 0xFF232F42)
    static let kbKeyOn = Color(awesun: 0xFF3B82F6)
    static let kbKeyText = Color(awesun: 0xFFF1F5FA)
    static let kbSecondText = Color(awesun: 0xFFA8B5C8)
    static let sheetFill = Color(awesun: 0xF2101622)
    static let textPrimary = Color.white
    static let textSecondary = Color(awesun: 0xFFD6E0EE)
    static let textTertiary = Color(awesun: 0xFF94A3B8)
    static let hairline = Color(awesun: 0x26FFFFFF)
    static let ripple = Color(awesun: 0xFF60A5FA).opacity(0.45)
    static let mouseFill = Color(awesun: 0xBA141B28)
    static let mouseStroke = Color.white.opacity(0.28)
    static let mouseActiveStroke = Color(awesun: 0xE693C5FD)
}

enum AwesunMetrics {
    // 键盘
    static let kbRowHeight: CGFloat = 33
    static let kbRowGap: CGFloat = 7
    static let kbKeyGap: CGFloat = 5
    static let kbKeyRadius: CGFloat = 8
    static let kbPadH: CGFloat = 2.5
    static let kbPadV: CGFloat = 5

    // 面板
    static let sheetRadius: CGFloat = 24
    static let sheetHPad: CGFloat = 20
    static let sheetTopPad: CGFloat = 18
    static let sheetBottomPad: CGFloat = 26
}

// MARK: - 圆角（Android 的 <corners bottomRightRadius> 之类）

struct AwesunCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func awesunCorners(_ radius: CGFloat, _ corners: UIRectCorner) -> some View {
        clipShape(AwesunCorners(radius: radius, corners: corners))
    }
}

// MARK: - 图片资源（Assets.xcassets/awesun_*）

enum AwesunIcons {
    static let mouse = "awesun_mouse"
    static let keyboard = "awesun_kbd"
    static let touch = "awesun_touch"
    static let lock = "awesun_lock"
    static let guide = "awesun_guide"
    static let shot = "awesun_shot"
    static let soundOn = "awesun_sound_on"
    static let soundOff = "awesun_sound_off"
    static let switchScreen = "awesun_switch"
    static let restart = "awesun_restart"
    static let more = "awesun_more"
    static let quit = "awesun_quit"
    static let empty = "awesun_empty"
    static let lockSheet = "awesun_lock_sheet"
    static let lockImage = "awesun_lock_img"
    static let lockHighlight = "awesun_lock_hl"
    static let hint = "awesun_hint"
    static let tips = "awesun_tips"
    static let arrow = "awesun_arrow"
}
