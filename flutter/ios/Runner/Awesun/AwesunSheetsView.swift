import SwiftUI

struct AwesunSheetShell<Content: View>: View {
    let title: String
    var titleImage: String? = nil
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AwesunPalette.textPrimary)
                if let titleImage {
                    Image(titleImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 17)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AwesunPalette.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AwesunPalette.padFillPressed))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("关闭"))
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

struct AwesunFunctionSheet: View {
    @ObservedObject var model: AwesunSessionModel
    let height: CGFloat
    @State private var editing = false
    @State private var picked: Int?

    private let quickIDs = ["quit", "shot", "sound", "screen", "chat", "actions"]
    private let keyboardIDs = ["kbd", "fullKeyboard", "layout", "keys", "game"]
    private let displayIDs = ["display", "quality"]
    private let accent = Color(awesun: 0xFF4B8DF8)
    private let surface = Color(awesun: 0xFF15181F)
    private let border = Color(awesun: 0xFF2A2F39)
    private let text = Color(awesun: 0xFFEEF1F6)
    private let secondary = Color(awesun: 0xFF99A2B2)

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(border)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .accessibilityHidden(true)
            HStack {
                Text("远程操作")
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.5)
                Spacer()
                Button(action: model.closeFunctions) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(surface))
                        .overlay(Circle().strokeBorder(border, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭")
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    quickActions
                    if item("mode") != nil || item("mouse") != nil {
                        touchControls
                    }
                    if !items(keyboardIDs).isEmpty {
                        section("键盘", keys: keyboardIDs)
                    }
                    section("显示与连接", keys: displayIDs)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: height)
        .foregroundColor(text)
        .buttonStyle(.plain)
        .background(Color(awesun: 0xFF0B0D11))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(border, lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                heading("会话")
                Spacer()
                Button {
                    editing.toggle()
                    picked = nil
                } label: {
                    Label(editing ? "完成" : "调整", systemImage: editing ? "checkmark" : "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(surface))
                        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
                }
                .foregroundColor(editing ? accent : secondary)
            }
            if editing {
                Text("依次点两项以交换位置")
                    .font(.system(size: 12))
                    .foregroundColor(secondary)
            }
            let columns = [GridItem(.adaptive(minimum: 68), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items(quickIDs), id: \.element.id) { index, entry in
                    Button {
                        if editing {
                            if let from = picked {
                                model.moveFunction(from: from, to: index)
                                picked = nil
                            } else {
                                picked = index
                            }
                        } else {
                            model.perform(entry)
                        }
                    } label: {
                        actionTile(entry, selected: picked == index)
                    }
                    .accessibilityAddTraits(picked == index ? .isSelected : [])
                }
            }
        }
    }

    private var touchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                heading("远控方式")
                Spacer()
                if let guide = item("guide") {
                    Button {
                        model.perform(guide)
                    } label: {
                        HStack(spacing: 4) {
                            Text("手势指南")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .frame(minHeight: 32)
                    }
                    .foregroundColor(accent)
                }
            }
            VStack(spacing: 0) {
                if item("mode") != nil {
                    HStack(spacing: 4) {
                        modeButton(.touch)
                        modeButton(.pointer)
                    }
                    .padding(4)
                    .background(Color(awesun: 0xFF0B0D11))
                    .cornerRadius(13)
                    .padding(12)
                }
                if item("mouse") != nil {
                    option("虚拟鼠标", icon: "cursorarrow", value: model.mouseVisible, action: model.setMouseVisible)
                    Divider().overlay(border).padding(.horizontal, 16)
                }
                option("锁定显示", icon: "lock", value: model.displayLocked, action: model.setDisplayLocked)
            }
            .background(surface)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(border, lineWidth: 1))
        }
    }

    private func modeButton(_ mode: AwesunMode) -> some View {
        let selected = model.mode == mode
        return Button {
            model.selectMode(mode)
        } label: {
            Label(mode.title, systemImage: mode == .touch ? "hand.tap" : "cursorarrow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? text : secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? accent.opacity(0.23) : Color.clear)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? accent.opacity(0.55) : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func option(_ title: String, icon: String, value: Bool, action: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: action)) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
        }
        .toggleStyle(SwitchToggleStyle(tint: accent))
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
    }

    private func section(_ title: String, keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: keys == keyboardIDs ? 88 : 140), spacing: 8)], spacing: 8) {
                ForEach(items(keys), id: \.element.id) { _, entry in
                    Button { model.perform(entry) } label: { actionTile(entry) }
                }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
            .foregroundColor(secondary)
    }

    private func actionTile(_ entry: AwesunFunctionItem, selected: Bool = false) -> some View {
        let destructive = entry.id == "quit"
        let tint = destructive ? Color(awesun: 0xFFFF646E) : accent
        return VStack(spacing: 8) {
            Image(systemName: symbol(entry))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14))
                .cornerRadius(11)
            Text(entry.title).font(.system(size: 12, weight: .medium))
                .foregroundColor(destructive ? tint : text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(selected ? accent.opacity(0.16) : surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(selected ? accent : border, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func symbol(_ entry: AwesunFunctionItem) -> String {
        if entry.symbol { return entry.icon }
        switch entry.id {
        case "shot": return "camera"
        case "sound": return model.soundOn ? "speaker.wave.2" : "speaker.slash"
        case "screen": return "rectangle.2.swap"
        case "kbd": return "keyboard"
        case "quit": return "power"
        default: return "ellipsis"
        }
    }

    private func items(_ ids: [String]) -> [(offset: Int, element: AwesunFunctionItem)] {
        Array(model.functions.enumerated()).filter { ids.contains($0.element.id) }
    }

    private func item(_ id: String) -> AwesunFunctionItem? {
        model.functions.first { $0.id == id }
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
                        .fill(isOn ? AwesunPalette.brandBlue : Color.clear)
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
                        .foregroundColor(AwesunPalette.mint)
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
                        .background(RoundedRectangle(cornerRadius: 4).fill(AwesunPalette.brandBlue))
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
                        .foregroundColor(AwesunPalette.mint)
                    Text("高性能模式").font(.system(size: 13, weight: .semibold))
                }
            }
            .tint(AwesunPalette.brandBlue)
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
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AwesunPalette.mint.opacity(0.22)))
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
                                .tint(AwesunPalette.brandBlue)
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
            .background(selected ? AwesunPalette.brandBlue.opacity(0.82) : Color.white.opacity(0.085))
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
    let width: CGFloat
    let maxHeight: CGFloat
    @State private var custom = false

    private var columnCount: Int { width < 360 ? 3 : 4 }
    private var inset: CGFloat { width > 700 ? 36 : 8 }
    private let spacing: CGFloat = 5
    private let tileHeight: CGFloat = 46

    var body: some View {
        VStack(spacing: 7) {
            header
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing),
                                        count: columnCount), spacing: spacing) {
                    if custom {
                        ForEach(model.accessoryShortcuts) { shortcut in
                            tile(shortcut, action: "自定义")
                        }
                    } else {
                        ForEach(AwesunKeyboardShortcut.common.indices, id: \.self) { index in
                            let item = AwesunKeyboardShortcut.common[index]
                            tile(item.shortcut, action: item.action)
                        }
                    }
                }
            }
            .frame(height: gridHeight)
        }
        .padding(.horizontal, inset)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(width: width)
        .background(AwesunPalette.keyboardDeck)
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    private var gridHeight: CGFloat {
        let count = custom ? model.accessoryShortcuts.count : AwesunKeyboardShortcut.common.count
        let rows = CGFloat((count + columnCount - 1) / columnCount)
        let preferred = rows * tileHeight + max(0, rows - 1) * spacing
        return min(preferred, max(tileHeight, maxHeight - 64))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("快捷键")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !model.accessoryShortcuts.isEmpty {
                tab("常用", selected: !custom) { custom = false }
                tab("我的", selected: custom) { custom = true }
            }
            Button(action: model.closeSheet) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("关闭快捷键")
        }
    }

    private func tab(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .frame(minWidth: 42, minHeight: 30)
                .background(selected ? AwesunPalette.brandBlue.opacity(0.55) : AwesunPalette.keyboardCap)
                .cornerRadius(7)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tile(_ shortcut: AwesunKeyboardShortcut, action: String) -> some View {
        Button {
            model.sendShortcut(shortcut)
        } label: {
            VStack(spacing: 4) {
                Text(shortcut.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                    .allowsTightening(true)
                Text(action)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .background(AwesunPalette.keyboardCap)
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(shortcut.title + "，" + action))
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
            .background(pressed ? AwesunPalette.brandBlue : Color.white.opacity(0.10))
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
