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
    @State private var advanced = false

    var body: some View {
        AwesunSheetShell(title: "显示设置", onClose: model.closeSheet) {
            HStack(spacing: 6) {
                tab("画面", icon: "display", value: false)
                tab("分辨率与高级", icon: "slider.horizontal.3", value: true)
            }
            .padding(4)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
            .padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.displayOptions.isEmpty {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    if advanced {
                        optionGroup("远端分辨率", columns: 2)
                        optionGroup("自定义缩放")
                        optionGroup("自定义画质")
                        optionGroup("显示选项", toggleRows: true)
                        optionGroup("虚拟显示器", columns: 2)
                    } else {
                        performanceCard
                        optionGroup("画面比例")
                        optionGroup("画质")
                        optionGroup("编码")
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: height)
            .foregroundColor(.white)
            .buttonStyle(.plain)
        }
    }

    private func tab(_ label: String, icon: String, value: Bool) -> some View {
        Button {
            advanced = value
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(advanced == value ? .white : AwesunPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(advanced == value ? Color.white.opacity(0.12) : .clear)
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(advanced == value ? .isSelected : [])
    }

    private var performanceCard: some View {
        let status = model.performance
        return VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: Binding(get: { status.enabled }, set: model.setPerformance)) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AwesunPalette.brandRed)
                    Text("高性能模式").font(.system(size: 13, weight: .semibold))
                }
            }
            .tint(AwesunPalette.brandRed)
            .disabled(!status.supported)
            if !status.supported {
                Text("需要支持固定帧率的 Windows 主机")
                    .font(.system(size: 11)).foregroundColor(AwesunPalette.textSecondary)
            } else {
                HStack(spacing: 5) {
                    Text("目标帧率").font(.system(size: 11)).foregroundColor(AwesunPalette.textSecondary)
                    ForEach([30, 60, 90, 120], id: \.self) { fps in
                        Button { model.setPerformanceTarget(fps) } label: {
                            chip(fps == status.target, String(fps))
                        }
                        .accessibilityLabel("目标帧率 \(fps)")
                    }
                }
                if status.enabled {
                    Text(status.effective.map { $0 > 0 ? "主机锁定 \($0) FPS" : "主机暂用自适应" }
                         ?? "正在确认主机设置")
                        .font(.system(size: 11, weight: .medium))
                    HStack(spacing: 11) {
                        metric("实测", status.measuredFps.map { "\($0) FPS" } ?? "—")
                        metric("Windows", status.gpuEncode.map { $0 ? "GPU 纹理" : "兼容路径" } ?? "检测中")
                        metric("iPhone", status.gpuDecode ? "GPU 纹理" : "兼容路径")
                    }
                }
            }
        }
        .padding(11)
        .background(Color(awesun: 0xFF211920))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AwesunPalette.brandRed.opacity(0.22)))
        .cornerRadius(10)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundColor(AwesunPalette.textSecondary)
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func optionGroup(_ group: String, columns: Int = 3, toggleRows: Bool = false) -> some View {
        let values = model.displayOptions.filter { $0.group == group }
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(group)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AwesunPalette.textSecondary)
                if toggleRows {
                    VStack(spacing: 1) {
                        ForEach(values) { item in
                            Toggle(item.title, isOn: Binding(
                                get: { item.selected }, set: { _ in model.selectDisplayOption(item.id) }))
                                .font(.system(size: 12))
                                .tint(AwesunPalette.brandRed)
                                .padding(.vertical, 3)
                        }
                    }
                    .padding(.horizontal, 9)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(8)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
                        ForEach(values) { item in
                            Button { model.selectDisplayOption(item.id) } label: {
                                chip(item.selected, item.title)
                            }
                            .accessibilityAddTraits(item.selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private func chip(_ selected: Bool, _ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: selected ? .semibold : .regular))
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 33)
            .padding(.horizontal, 2)
            .foregroundColor(.white)
            .background(selected ? AwesunPalette.brandRed.opacity(0.82) : Color.white.opacity(0.085))
            .cornerRadius(7)
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
