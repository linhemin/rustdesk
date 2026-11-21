import SwiftUI

/// 底部面板壳（OD4.xml：85% 黑 + 上 16dp 圆角）
struct AwesunSheetShell<Content: View>: View {
    let title: String
    var titleImage: String? = nil
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AwesunPalette.textPrimary)
                    if let titleImage {
                        Image(titleImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 17)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(.horizontal, AwesunMetrics.sheetHPad)
        .padding(.top, AwesunMetrics.sheetTopPad)
        .padding(.bottom, AwesunMetrics.sheetBottomPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AwesunPalette.sheetFill)
        .awesunCorners(AwesunMetrics.sheetRadius, [.topLeft, .topRight])
    }
}

struct AwesunBullet: View {
    let marker: String
    let text: String
    var secondary: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var color: Color {
        secondary ? AwesunPalette.textTertiary : AwesunPalette.textSecondary
    }
}

/// 远程操作九宫格（长按进入排序，再点另一项交换）
struct AwesunFunctionSheet: View {
    @ObservedObject var model: AwesunSessionModel
    @State private var editing = false
    @State private var picked: Int? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        AwesunSheetShell(title: "远程操作", onClose: { model.closeFunctions() }) {
            Text(editing ? "点另一个图标即可交换位置" : "长按图标可调整位置")
                .font(.system(size: 11))
                .foregroundColor(AwesunPalette.textTertiary)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(model.functions.enumerated()), id: \.element.id) { index, item in
                    Button {
                        if editing {
                            if let from = picked {
                                model.moveFunction(from: from, to: index)
                                picked = nil
                                editing = false
                            } else {
                                picked = index
                            }
                        } else {
                            model.perform(item)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Group {
                                if item.symbol {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                } else {
                                    Image(item.icon).resizable().scaledToFit()
                                }
                            }
                            .frame(width: 24, height: 24)
                            Text(item.title)
                                .font(.system(size: 11))
                                .foregroundColor(Color(awesun: 0xFFE8EEF3))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(picked == index ? 0.16 : 0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(picked == index ? 0.35 : 0),
                                              lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture(minimumDuration: 0.35) {
                        editing = true
                        picked = index
                        model.haptic(.light)
                    }
                }
            }
            .padding(.top, 10)
        }
    }
}

/// 手机模式
struct AwesunModeSheet: View {
    @ObservedObject var model: AwesunSessionModel

    var body: some View {
        AwesunSheetShell(title: "手机模式", onClose: { model.closeSheet() }) {
            HStack(spacing: 10) {
                segment(.pointer)
                segment(.touch)
            }
            .padding(.top, 16)

            row(label: "虚拟鼠标") {
                AwesunSwitch(isOn: Binding(
                    get: { model.mouseVisible },
                    set: { value in
                        model.setMouseVisible(value)
                    }
                ))
            }
            .padding(.top, 14)

            row(label: "锁定显示") {
                AwesunSwitch(isOn: Binding(
                    get: { model.displayLocked },
                    set: { model.setDisplayLocked($0) }
                ))
            }
            .padding(.top, 14)

            HStack(spacing: 2) {
                Spacer()
                Text("手势指南")
                    .font(.system(size: 13))
                    .foregroundColor(AwesunPalette.brandBlue)
                Image(AwesunIcons.arrow)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 12)
            }
            .padding(.top, 16)
            .contentShape(Rectangle())
            .onTapGesture { model.sheet = .guide }

            AwesunBullet(marker: "·", text: "自动完成画面校准，自动裁剪画面多余黑边")
            AwesunBullet(marker: "*", text: "若被控是 iOS 设备，请在手机开启「辅助触控」", secondary: true)
        }
    }

    private func segment(_ mode: AwesunMode) -> some View {
        let isOn = model.mode == mode
        return Button {
            model.selectMode(mode)
        } label: {
            Text(mode.title)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isOn ? AwesunPalette.brandRed : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isOn ? Color.clear : Color(awesun: 0xFF929293), lineWidth: 2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row<Content: View>(label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white)
            if label == "锁定显示" {
                Image(AwesunIcons.tips)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 14)
                    .opacity(0.7)
            }
            Spacer()
            trailing()
        }
    }
}

/// 锁定显示
struct AwesunLockSheet: View {
    @ObservedObject var model: AwesunSessionModel

    var body: some View {
        AwesunSheetShell(title: "锁定显示",
                         titleImage: AwesunIcons.lockSheet,
                         onClose: { model.closeSheet() }) {
            Text("适用于折叠屏/平板等大屏设备，远控电脑软件就像操作手机 APP 一样。锁定前，建议横屏显示整个桌面。")
                .font(.system(size: 13))
                .foregroundColor(AwesunPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            ZStack(alignment: .topTrailing) {
                Image(AwesunIcons.lockImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
                Image(AwesunIcons.lockHighlight)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 84)
                    .padding(8)
            }
            .padding(.top, 14)

            Text("* Win10 以下系统部分手势可能无效")
                .font(.system(size: 12))
                .foregroundColor(AwesunPalette.textTertiary)
                .padding(.top, 12)

            HStack(spacing: 12) {
                Button {
                    model.closeSheet()
                } label: {
                    Text("取消")
                        .font(.system(size: 15))
                        .foregroundColor(AwesunPalette.brandRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)

                Button {
                    model.setDisplayLocked(!model.displayLocked)
                    model.closeSheet()
                } label: {
                    Text(model.displayLocked ? "取消锁定" : "立即锁定")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 4).fill(AwesunPalette.brandRed))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
        }
    }
}

/// 手势指南
struct AwesunGuideSheet: View {
    @ObservedObject var model: AwesunSessionModel

    private let items: [(String, String)] = [
        ("单指点按", "左键单击"),
        ("长按 0.48s", "右键单击"),
        ("按住移动", "拖拽 / 移动光标"),
        ("双指滑动", "滚轮上下"),
        ("双指捏合", "画面缩放"),
        ("双击", "双击打开"),
    ]

    var body: some View {
        AwesunSheetShell(title: "手势指南", onClose: { model.closeSheet() }) {
            Text("当前：\(model.mode.title)")
                .font(.system(size: 12))
                .foregroundColor(AwesunPalette.textTertiary)
                .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.0)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        Spacer()
                        Text(item.1)
                            .font(.system(size: 13))
                            .foregroundColor(AwesunPalette.textSecondary)
                    }
                    .padding(.vertical, 9)
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
            .padding(.top, 6)

            AwesunBullet(marker: "*", text: "若被控使用黑色壁纸或画面有黑边，可能会有校准误差", secondary: true)
        }
    }
}

/// Android 风格开关
struct AwesunSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AwesunPalette.brandBlue : Color.white.opacity(0.24))
                    .frame(width: 40, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AwesunDisplayPanel: View {
    @ObservedObject var model: AwesunSessionModel
    let height: CGFloat

    var body: some View {
        AwesunSheetShell(title: "显示设置", onClose: model.closeSheet) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if model.displayOptions.isEmpty {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    ForEach(["画面比例", "画质", "编码", "显示选项"], id: \.self) { group in
                        let options = model.displayOptions.filter { $0.group == group }
                        if !options.isEmpty {
                            Text(group)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AwesunPalette.textSecondary)
                            if group == "显示选项" {
                                VStack(spacing: 1) {
                                    ForEach(options) { item in
                                        Toggle(item.title, isOn: Binding(
                                            get: { item.selected },
                                            set: { _ in model.selectDisplayOption(item.id) }
                                        ))
                                        .font(.system(size: 14))
                                        .tint(AwesunPalette.brandRed)
                                        .padding(.vertical, 5)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(10)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 7) {
                                    ForEach(options) { item in
                                        Button { model.selectDisplayOption(item.id) } label: {
                                            Text(item.title)
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.7)
                                                .multilineTextAlignment(.center)
                                                .frame(maxWidth: .infinity, minHeight: 38)
                                                .background(item.selected
                                                            ? AwesunPalette.brandRed
                                                            : Color.white.opacity(0.10))
                                                .cornerRadius(8)
                                        }
                                        .accessibilityAddTraits(item.selected ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }
                    Button(action: model.openAdvancedDisplay) {
                        AwesunActionRow(icon: "slider.horizontal.3", title: "分辨率与高级设置")
                    }
                }
            }
            .frame(maxHeight: height)
            .foregroundColor(.white)
            .padding(.top, 12)
            .buttonStyle(.plain)
        }
    }
}

struct AwesunActionPanel: View {
    @ObservedObject var model: AwesunSessionModel
    let height: CGFloat

    var body: some View {
        AwesunSheetShell(title: "更多操作", onClose: model.closeSheet) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(model.actions.enumerated()), id: \.offset) { index, title in
                        Button { model.chooseAction(index) } label: {
                            AwesunActionRow(icon: symbol(for: title), title: title)
                        }
                    }
                }
            }
            .frame(maxHeight: height)
            .padding(.top, 12)
            .buttonStyle(.plain)
        }
    }

    private func symbol(for title: String) -> String {
        let text = title.lowercased()
        if text.contains("p2p") || text.contains("复制") || text.contains("copy") { return "doc.on.doc" }
        if text.contains("光标") || text.contains("cursor") { return "scope" }
        if text.contains("刷新") || text.contains("refresh") { return "arrow.clockwise" }
        if text.contains("密码") || text.contains("password") { return "key" }
        if text.contains("录制") || text.contains("record") { return "record.circle" }
        if text.contains("重启") || text.contains("restart") { return "power" }
        return "bolt"
    }
}

struct AwesunActionRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.12))
                .cornerRadius(7)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AwesunPalette.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 46)
        .background(Color.white.opacity(0.07))
        .cornerRadius(9)
        .contentShape(Rectangle())
    }
}

struct AwesunShortcutPanel: View {
    @ObservedObject var model: AwesunSessionModel
    let height: CGFloat

    var body: some View {
        AwesunSheetShell(title: "快捷键", onClose: model.closeSheet) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(AwesunKeyboardShortcut.common) { shortcut in
                        Button { model.sendShortcut(shortcut) } label: {
                            HStack(spacing: 4) {
                                ForEach(shortcut.labels, id: \.self) { label in
                                    Text(label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                        .padding(.horizontal, 5)
                                        .frame(minHeight: 23)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(5)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        }
                        .accessibilityLabel(Text(shortcut.id))
                    }
                }
            }
            .foregroundColor(.white)
            .frame(maxHeight: height)
            .padding(.top, 12)
            .buttonStyle(.plain)
        }
    }
}

struct AwesunGamePanel: View {
    @ObservedObject var model: AwesunSessionModel
    private let rows = [["W", "Up", "Space"], ["A", "S", "D"], ["Left", "Down", "Right"]]

    var body: some View {
        AwesunSheetShell(title: "游戏键盘", onClose: model.closeSheet) {
            VStack(spacing: 7) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 7) {
                        ForEach(row, id: \.self) { label in
                            if let key = AwesunKeyboardLayout.selectableKeys.first(where: { $0.label == label }) {
                                AwesunGameButton(key: key)
                            }
                        }
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}

private struct AwesunGameButton: View {
    let key: AwesunKeySpec
    @GestureState private var pressed = false
    @State private var sent = false

    var body: some View {
        Text(key.label)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(pressed ? AwesunPalette.brandRed : Color.white.opacity(0.10))
            .cornerRadius(8)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($pressed) { _, value, _ in value = true }
                .onChanged { _ in
                    guard !sent else { return }
                    sent = true
                    AwesunBridge.shared.key(key.vk, down: true)
                }
                .onEnded { _ in release() })
            .onChange(of: pressed) { value in if !value { release() } }
            .onDisappear { release() }
    }

    private func release() {
        guard sent else { return }
        sent = false
        AwesunBridge.shared.key(key.vk, down: false)
    }
}
