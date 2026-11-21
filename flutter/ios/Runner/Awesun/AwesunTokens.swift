import SwiftUI
import UIKit

// MARK: - Session design tokens

extension Color {
    init(workspaceLight light: UInt32, dark: UInt32) {
        self = Color(UIColor { traits in
            let argb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((argb >> 16) & 0xFF) / 255,
                green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255,
                alpha: CGFloat((argb >> 24) & 0xFF) / 255)
        })
    }

    init(awesun argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum AwesunPalette {
    static let padFill = Color(awesun: 0xFF1A2436)
    static let padFillPressed = Color(awesun: 0xFF303E54)
    static let padStroke = Color(awesun: 0xFF465670)
    static let dpadFill = Color(awesun: 0xFF243149)
    static let mint = Color(awesun: 0xFFC7D2FE)
    static let hudFill = Color(awesun: 0xFF101725)
    static let hudLabel = Color(awesun: 0xFF9AA9BF)
    static let hudValue = Color(awesun: 0xFFFFFFFF)
    static let hudGreen = Color(awesun: 0xFF4FD1A1)
    static let pairFill = Color(awesun: 0xFF1A2436)
    static let pairStroke = Color(awesun: 0xFF465670)
    static let glyph = Color(awesun: 0xFFF4FAFF)

    static let brandBlue = Color(workspaceLight: 0xFF4263EB, dark: 0xFFA5B4FC)
    static let brandRed = Color(awesun: 0xFFEF6685)
    static let kbBackground = Color(workspaceLight: 0xFFF4F6FA, dark: 0xFF101725)
    static let kbKey = Color(workspaceLight: 0xFFFFFFFF, dark: 0xFF303E54)
    static let kbKeyOn = Color(awesun: 0xFF4263EB)
    static let kbKeyText = Color(workspaceLight: 0xFF17233B, dark: 0xFFE8EDF7)
    static let kbSecondText = Color(workspaceLight: 0xFF66758C, dark: 0xFF9AA9BF)
    static let sheetFill = Color(workspaceLight: 0xFFFFFFFF, dark: 0xFF1A2436)
    static let textPrimary = Color(workspaceLight: 0xFF17233B, dark: 0xFFE8EDF7)
    static let textSecondary = Color(workspaceLight: 0xFF66758C, dark: 0xFFD3DCEC)
    static let textTertiary = Color(workspaceLight: 0xFF66758C, dark: 0xFF9AA9BF)
    static let hairline = Color(workspaceLight: 0xFFE2E7F0, dark: 0xFF303E54)
    static let controlFill = Color(workspaceLight: 0xFFF4F6FA, dark: 0xFF303E54)
    static let onAccent = Color.white
    static let ripple = Color(awesun: 0xFFB2B2B2).opacity(100.0 / 255.0)
    static let mouseFill = Color.white.opacity(0.61)
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
