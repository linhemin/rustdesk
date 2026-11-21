import SwiftUI
import UIKit

// MARK: - 设计令牌
//
// 数值全部来自对 APK 资源（resources.arsc / drawable AXML）与真机会话截图
// （1080×2348，px/pt ≈ 2.77）的逐项测量，换算到 393×852pt 基准。

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
    // 会话主界面（真机截图取样）
    static let padFill = Color(awesun: 0xFF1A232A)
    static let padFillPressed = Color(awesun: 0xFF2A3742)
    static let padStroke = Color(awesun: 0xFF3A424A)
    static let dpadFill = Color(awesun: 0xFF232C34)
    static let mint = Color(awesun: 0xFFBEF2E2)
    static let hudFill = Color(awesun: 0xFF131313)
    static let hudLabel = Color(awesun: 0xFFB9B9B9)
    static let hudValue = Color(awesun: 0xFFFFFFFF)
    static let hudGreen = Color(awesun: 0xFF59B761)
    static let pairFill = Color(awesun: 0xFF161D25)
    static let pairStroke = Color(awesun: 0x59788C9B)
    static let glyph = Color(awesun: 0xFFF4FAFF)

    // APK 资源实测
    static let brandBlue = Color(awesun: 0xFF3773F5)
    static let brandRed = Color(awesun: 0xFFDD3A5F)
    static let kbBackground = Color(awesun: 0xFFA9B8C1)
    static let kbKey = Color.white
    static let kbKeyOn = Color(awesun: 0xE6000000)
    static let kbKeyText = Color(awesun: 0xFF4A4A4A)
    static let kbSecondText = Color(awesun: 0xFF9A9A9A)
    static let sheetFill = Color(awesun: 0xD9000000)
    static let textPrimary = Color.white
    static let textSecondary = Color(awesun: 0xFFC9CDD4)
    static let textTertiary = Color(awesun: 0xFFA8A9AD)
    static let hairline = Color(awesun: 0x33FFFFFF)
    static let ripple = Color(awesun: 0xFFB2B2B2).opacity(100.0 / 255.0)
    static let mouseFill = Color.white.opacity(0.61)
}

enum AwesunMetrics {
    // 键盘
    static let kbRowHeight: CGFloat = 33
    static let kbRowGap: CGFloat = 7
    static let kbKeyGap: CGFloat = 5
    static let kbKeyRadius: CGFloat = 5
    static let kbPadH: CGFloat = 2.5
    static let kbPadV: CGFloat = 5

    // 面板
    static let sheetRadius: CGFloat = 16
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
