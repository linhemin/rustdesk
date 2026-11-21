import SwiftUI

/// 单键：label / 第二字符 / VK 名称 / 权重 / 是否修饰键
struct AwesunKeySpec: Identifiable {
    let id = UUID()
    var label: String = ""
    var second: String? = nil
    var vk: String = ""
    var weight: CGFloat = 1
    var isModifier: Bool = false
    var isSpacer: Bool = false

    static let spacer = AwesunKeySpec(isSpacer: true)
}

/// 86 键 / 9 行，键位与 APK 的 1ky.xml 一致
enum AwesunKeyboardLayout {
    static let rows: [[AwesunKeySpec]] = [
        [
            AwesunKeySpec(label: "Ctrl", vk: "VK_CONTROL", isModifier: true),
            AwesunKeySpec(label: "Shift", vk: "VK_SHIFT", isModifier: true),
            AwesunKeySpec(label: "Alt", vk: "VK_MENU", isModifier: true),
            AwesunKeySpec(label: "Caps", vk: "VK_CAPITAL", isModifier: true),
            AwesunKeySpec(label: "Win", vk: "VK_LWIN"),
            AwesunKeySpec(label: "左键", vk: "MOUSE_LEFT"),
            AwesunKeySpec(label: "中键", vk: "MOUSE_MIDDLE"),
            AwesunKeySpec(label: "右键", vk: "MOUSE_RIGHT"),
        ],
        "QWERTYUIOP".map { AwesunKeySpec(label: String($0), vk: "VK_\($0)") },
        "ASDFGHJKL".map { AwesunKeySpec(label: String($0), vk: "VK_\($0)") }
            + [AwesunKeySpec(label: "BackSpace", vk: "VK_BACK")],
        "ZXCVBNM".map { AwesunKeySpec(label: String($0), vk: "VK_\($0)") }
            + [AwesunKeySpec(label: "Space", vk: "VK_SPACE", weight: 1.5),
               AwesunKeySpec(label: "Enter", vk: "VK_ENTER", weight: 1.5)],
        "1234567890".map { AwesunKeySpec(label: String($0), vk: "VK_\($0)") },
        [
            AwesunKeySpec(label: "F1", vk: "VK_F1"), AwesunKeySpec(label: "F2", vk: "VK_F2"),
            AwesunKeySpec(label: "F3", vk: "VK_F3"), AwesunKeySpec(label: "F4", vk: "VK_F4"),
            AwesunKeySpec(label: "`", second: "~", vk: "VK_OEM_3"),
            AwesunKeySpec(label: "Esc", vk: "VK_ESCAPE"), AwesunKeySpec(label: "Tab", vk: "VK_TAB"),
            AwesunKeySpec(label: "PrtScr", vk: "VK_SNAPSHOT"),
            AwesunKeySpec(label: "ScrLK", vk: "VK_SCROLL"),
            AwesunKeySpec(label: "Pause", vk: "VK_PAUSE"),
        ],
        [
            AwesunKeySpec(label: "F5", vk: "VK_F5"), AwesunKeySpec(label: "F6", vk: "VK_F6"),
            AwesunKeySpec(label: "F7", vk: "VK_F7"), AwesunKeySpec(label: "F8", vk: "VK_F8"),
            AwesunKeySpec.spacer,
            AwesunKeySpec(label: "Up", vk: "VK_UP"),
            AwesunKeySpec(label: "NumLK", vk: "VK_NUMLOCK"),
            AwesunKeySpec(label: "Ins", vk: "VK_INSERT"),
            AwesunKeySpec(label: "Home", vk: "VK_HOME"),
            AwesunKeySpec(label: "PgUp", vk: "VK_PRIOR"),
        ],
        [
            AwesunKeySpec(label: "F9", vk: "VK_F9"), AwesunKeySpec(label: "F10", vk: "VK_F10"),
            AwesunKeySpec(label: "F11", vk: "VK_F11"), AwesunKeySpec(label: "F12", vk: "VK_F12"),
            AwesunKeySpec(label: "Left", vk: "VK_LEFT"),
            AwesunKeySpec(label: "Down", vk: "VK_DOWN"),
            AwesunKeySpec(label: "Right", vk: "VK_RIGHT"),
            AwesunKeySpec(label: "Del", vk: "VK_DELETE"),
            AwesunKeySpec(label: "End", vk: "VK_END"),
            AwesunKeySpec(label: "PgDn", vk: "VK_NEXT"),
        ],
        [
            AwesunKeySpec(label: "-", second: "_", vk: "VK_OEM_MINUS"),
            AwesunKeySpec(label: "=", second: "+", vk: "VK_OEM_PLUS"),
            AwesunKeySpec(label: "[", second: "{", vk: "VK_OEM_4"),
            AwesunKeySpec(label: "]", second: "}", vk: "VK_OEM_6"),
            AwesunKeySpec(label: "\\", second: "|", vk: "VK_OEM_5"),
            AwesunKeySpec(label: ";", second: ":", vk: "VK_OEM_1"),
            AwesunKeySpec(label: "'", second: "\"", vk: "VK_OEM_7"),
            AwesunKeySpec(label: "，", second: "<", vk: "VK_OEM_COMMA"),
            AwesunKeySpec(label: ".", second: ">", vk: "VK_OEM_PERIOD"),
            AwesunKeySpec(label: "/", second: "?", vk: "VK_OEM_2"),
        ],
    ]
}

struct AwesunKeyboardView: View {
    @ObservedObject var model: AwesunSessionModel

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: AwesunMetrics.kbRowGap) {
                ForEach(Array(AwesunKeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
            }
            .padding(.horizontal, AwesunMetrics.kbPadH)
            .padding(.vertical, AwesunMetrics.kbPadV)
        }
        .background(AwesunPalette.kbBackground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(model.inputEcho.isEmpty ? "输入内容" : model.inputEcho)
                .font(.system(size: 13))
                .foregroundColor(model.inputEcho.isEmpty
                                 ? Color(awesun: 0xFF5C6B73)
                                 : Color(awesun: 0xFF1F2A30))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !model.modifiers.isEmpty {
                Text(model.modifiers.sorted().joined(separator: " + "))
                    .font(.system(size: 11))
                    .foregroundColor(Color(awesun: 0xFF1F2A30))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.5)))
            }

            Button {
                model.haptic(.light)
                model.closeKeyboard()
            } label: {
                Text("收起")
                    .font(.system(size: 12))
                    .foregroundColor(Color(awesun: 0xFF1F2A30))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.55)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func rowView(_ row: [AwesunKeySpec]) -> some View {
        GeometryReader { geo in
            let gap = AwesunMetrics.kbKeyGap
            let totalWeight = row.reduce(CGFloat(0)) { $0 + $1.weight }
            let usable = max(geo.size.width - gap * CGFloat(max(row.count - 1, 1)), 10)
            let unit = usable / max(totalWeight, 1)

            HStack(spacing: gap) {
                ForEach(row) { spec in
                    if spec.isSpacer {
                        Color.clear
                            .frame(width: unit * spec.weight, height: AwesunMetrics.kbRowHeight)
                    } else {
                        keyCap(spec, width: unit * spec.weight)
                    }
                }
            }
        }
        .frame(height: AwesunMetrics.kbRowHeight)
    }

    private func keyCap(_ spec: AwesunKeySpec, width: CGFloat) -> some View {
        let isOn = model.modifiers.contains(spec.label)
        let isPressed = model.pressedKeycap == spec.label
        return Button {
            model.pressKey(spec)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(spec.label)
                    .font(.system(size: 13))
                    .foregroundColor(isOn ? .white : AwesunPalette.kbKeyText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: width, height: AwesunMetrics.kbRowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: AwesunMetrics.kbKeyRadius, style: .continuous)
                            .fill(isOn ? AwesunPalette.kbKeyOn : AwesunPalette.kbKey)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AwesunMetrics.kbKeyRadius, style: .continuous)
                            .strokeBorder(isOn || isPressed ? AwesunPalette.brandBlue : Color.clear,
                                          lineWidth: 2)
                    )

                if let second = spec.second {
                    Text(second)
                        .font(.system(size: 9))
                        .foregroundColor(isOn ? Color.white.opacity(0.8) : AwesunPalette.kbSecondText)
                        .padding(.top, 3)
                        .padding(.trailing, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AwesunKeyboardShortcut: Identifiable, Codable {
    let labels: [String]
    let key: String
    let modifiers: [String]
    var storageID: String? = nil
    var title: String { labels.joined(separator: "+") }
    var id: String { storageID ?? title }

    static let modifierOptions = [("Ctrl", "ctrl"), ("Shift", "shift"), ("Alt", "alt"), ("Win", "meta")]
    static let storageKey = "awesun.keyboard.chords.v1"

    static func saved() -> [Self] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }

    static let common: [(shortcut: AwesunKeyboardShortcut, action: String)] = [
        (Self(labels: ["Ctrl", "C"], key: "VK_C", modifiers: ["ctrl"]), "复制"),
        (Self(labels: ["Ctrl", "V"], key: "VK_V", modifiers: ["ctrl"]), "粘贴"),
        (Self(labels: ["Ctrl", "X"], key: "VK_X", modifiers: ["ctrl"]), "剪切"),
        (Self(labels: ["Ctrl", "A"], key: "VK_A", modifiers: ["ctrl"]), "全选"),
        (Self(labels: ["Ctrl", "Z"], key: "VK_Z", modifiers: ["ctrl"]), "撤销"),
        (Self(labels: ["Ctrl", "S"], key: "VK_S", modifiers: ["ctrl"]), "保存"),
        (Self(labels: ["Win", "D"], key: "VK_D", modifiers: ["meta"]), "显示桌面"),
        (Self(labels: ["Win", "Tab"], key: "VK_TAB", modifiers: ["meta"]), "任务视图"),
        (Self(labels: ["Alt", "F4"], key: "VK_F4", modifiers: ["alt"]), "关闭窗口"),
        (Self(labels: ["Win", "R"], key: "VK_R", modifiers: ["meta"]), "运行"),
        (Self(labels: ["Win", "L"], key: "VK_L", modifiers: ["meta"]), "锁定系统"),
        (Self(labels: ["Win", "E"], key: "VK_E", modifiers: ["meta"]), "资源管理器"),
        (Self(labels: ["Ctrl", "Shift", "Esc"], key: "VK_ESCAPE", modifiers: ["ctrl", "shift"]), "任务管理器"),
        (Self(labels: ["Ctrl", "Alt", "Del"], key: "secure-attention", modifiers: []), "安全选项"),
        (Self(labels: ["Alt", "PrtScr"], key: "VK_SNAPSHOT", modifiers: ["alt"]), "窗口截图"),
        (Self(labels: ["Win", "Q"], key: "VK_Q", modifiers: ["meta"]), "搜索"),
        (Self(labels: ["Alt", "Tab"], key: "VK_TAB", modifiers: ["alt"]), "切换窗口")
    ]

}

extension AwesunKeyboardLayout {
    static let accessoryStorage = "awesun.keyboard.accessory.v1"
    static let defaultAccessory = ["VK_CONTROL", "VK_SHIFT", "VK_MENU", "VK_LWIN"]
    static let selectableKeys = rows.flatMap { $0 }.filter { !$0.isSpacer && !$0.vk.isEmpty }
    static let keyByCode = Dictionary(selectableKeys.map { ($0.vk, $0) }, uniquingKeysWith: { first, _ in first })

    static func savedAccessoryKeys() -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: accessoryStorage) ?? defaultAccessory
        var used = Set<String>()
        let chordIDs = Set(AwesunKeyboardShortcut.saved().map(\.id))
        return stored.filter {
            (keyByCode[$0] != nil || chordIDs.contains($0)) && used.insert($0).inserted
        }
    }

    static func modifierName(for key: String) -> String? {
        switch key {
        case "VK_CONTROL": return "Ctrl"
        case "VK_SHIFT": return "Shift"
        case "VK_MENU": return "Alt"
        case "VK_LWIN": return "Win"
        default: return nil
        }
    }

    static func title(for key: AwesunKeySpec) -> String {
        switch key.vk {
        case "VK_BACK": return "退格"
        case "VK_DELETE": return "Del"
        default: return key.label
        }
    }
}

struct AwesunKeyboardDeck<Accessory: View>: View {
    @ObservedObject var model: AwesunSessionModel
    let height: CGFloat
    @ViewBuilder var accessory: () -> Accessory

    private let navigation = [
        ["VK_SNAPSHOT", "VK_SCROLL", "VK_PAUSE"],
        ["VK_INSERT", "VK_HOME", "VK_PRIOR"],
        ["VK_DELETE", "VK_END", "VK_NEXT"],
        ["VK_ESCAPE", "VK_UP", "VK_TAB"],
        ["VK_LEFT", "VK_DOWN", "VK_RIGHT"]
    ]

    var body: some View {
        VStack(spacing: 4) {
            accessory()
            HStack(spacing: 4) {
                keyGroup((0..<4).map { index in
                    (1...3).map { "VK_F" + String(index * 3 + $0) }
                })
                keyGroup(navigation)
            }
            .frame(height: height)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(AwesunPalette.keyboardDeck)
    }

    private func keyGroup(_ rows: [[String]]) -> some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { code in
                        if let key = AwesunKeyboardLayout.keyByCode[code] {
                            Button { model.sendAccessoryKey(key) } label: {
                                AwesunKeyTile(title: AwesunKeyTile.label(key), expanded: true)
                            }
                            .accessibilityLabel(Text(key.label))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct AwesunKeyTile: View {
    let title: String
    var second: String? = nil
    var selected = false
    var expanded = false

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: expanded ? 13 : 12, weight: selected ? .semibold : .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
            if let second = second {
                Text(second)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundColor(.white)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: expanded ? .infinity : nil)
        .frame(minHeight: expanded ? 0 : 39)
        .background(selected ? AwesunPalette.brandRed.opacity(0.78) : AwesunPalette.keyboardCap)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    static func label(_ key: AwesunKeySpec) -> String {
        switch key.vk {
        case "VK_LEFT": return "←"
        case "VK_UP": return "↑"
        case "VK_DOWN": return "↓"
        case "VK_RIGHT": return "→"
        case "VK_INSERT": return "Insert"
        case "VK_SPACE": return "空格"
        default: return AwesunKeyboardLayout.title(for: key)
        }
    }
}

extension AwesunPalette {
    static let keyboardDeck = Color(awesun: 0xFF171522)
    static let keyboardCap = Color(awesun: 0xFF292834)
}

struct AwesunAccessorySlot: Equatable {
    let key: String
    var modifiers: Set<String> = []

    var title: String {
        let keyName = AwesunKeyboardLayout.keyByCode[key].map(AwesunKeyTile.label) ?? key
        let labels = AwesunKeyboardShortcut.modifierOptions.filter { modifiers.contains($0.1) }.map { $0.0 }
        return (labels + [keyName]).joined(separator: "+")
    }

    var shortcut: AwesunKeyboardShortcut {
        let selected = AwesunKeyboardShortcut.modifierOptions.filter { modifiers.contains($0.1) }
        let keyName = AwesunKeyboardLayout.keyByCode[key].map(AwesunKeyTile.label) ?? key
        let secure = key == "VK_DELETE" && modifiers == Set(["ctrl", "alt"])
        return AwesunKeyboardShortcut(labels: selected.map { $0.0 } + [keyName],
                                      key: secure ? "secure-attention" : key,
                                      modifiers: selected.map { $0.1 },
                                      storageID: "chord-" + UUID().uuidString)
    }
}

struct AwesunAccessoryEditor: View {
    @ObservedObject var model: AwesunSessionModel
    let height: CGFloat
    @State private var slots: [AwesunAccessorySlot?]
    @State private var selected: Int
    @State private var modifiers: Set<String> = []

    init(model: AwesunSessionModel, height: CGFloat) {
        self.model = model
        self.height = height
        let existing = model.editableAccessorySlots
        _slots = State(initialValue: existing.map(Optional.some) + [nil])
        _selected = State(initialValue: existing.count)
    }

    private let keyRows: [[String]] = [
        ["VK_CONTROL", "VK_SHIFT", "VK_MENU", "VK_LWIN", "VK_CAPITAL", "MOUSE_LEFT", "MOUSE_MIDDLE", "MOUSE_RIGHT"],
        "QWERTYUIOP".map { "VK_" + String($0) },
        "ASDFGHJKL".map { "VK_" + String($0) } + ["VK_BACK"],
        "ZXCVBNM".map { "VK_" + String($0) } + ["VK_SPACE", "VK_ENTER"],
        "1234567890".map { "VK_" + String($0) },
        (1...6).map { "VK_F" + String($0) },
        (7...12).map { "VK_F" + String($0) },
        ["VK_INSERT", "VK_HOME", "VK_PRIOR", "VK_SNAPSHOT", "VK_SCROLL", "VK_PAUSE"],
        ["VK_DELETE", "VK_END", "VK_NEXT", "VK_ESCAPE", "VK_UP", "VK_TAB"],
        ["VK_OEM_3", "VK_OEM_MINUS", "VK_OEM_PLUS", "VK_LEFT", "VK_DOWN", "VK_RIGHT"],
        ["VK_OEM_4", "VK_OEM_6", "VK_OEM_5", "VK_OEM_1", "VK_OEM_7", "VK_OEM_COMMA", "VK_OEM_PERIOD", "VK_OEM_2"]
    ]

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Button("取消", action: model.closeSheet)
                Spacer()
                Text("自定义键盘栏")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("完成") {
                    var value = slots
                    if value[selected] == nil, let single = singleModifier {
                        value[selected] = AwesunAccessorySlot(key: single)
                    }
                    model.replaceAccessorySlots(value.compactMap { $0 })
                    model.closeSheet()
                }
                .font(.system(size: 13, weight: .semibold))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(slots.indices, id: \.self) { index in
                        Button {
                            selected = index
                            modifiers = []
                        } label: {
                            AwesunKeyTile(title: slots[index]?.title ?? "选键", selected: index == selected)
                                .frame(width: 77)
                        }
                        .accessibilityAddTraits(index == selected ? .isSelected : [])
                    }
                }
            }
            HStack {
                Text(preview)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let single = singleModifier {
                    Button("仅添加修饰键") { assign(AwesunAccessorySlot(key: single)) }
                }
                Button("清空此槽") {
                    slots[selected] = nil
                    modifiers = []
                }
                .disabled(slots[selected] == nil)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 5)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(keyRows, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(row, id: \.self) { code in
                                if let key = AwesunKeyboardLayout.keyByCode[code] {
                                    let on = AwesunKeyboardLayout.modifierName(for: code).map { modifiers.contains($0) } ?? false
                                    Button { choose(key) } label: {
                                        AwesunKeyTile(title: AwesunKeyTile.label(key), second: key.second, selected: on)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: max(100, height - 120))
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .padding(.horizontal, 5)
        .padding(.bottom, 8)
        .background(AwesunPalette.keyboardDeck)
    }

    private var singleModifier: String? {
        guard modifiers.count == 1, let modifier = modifiers.first else { return nil }
        return AwesunKeyboardLayout.defaultAccessory.first {
            AwesunKeyboardLayout.modifierName(for: $0) == modifier
        }
    }

    private var preview: String {
        guard !modifiers.isEmpty else { return slots[selected]?.title ?? "选择单键，或先点修饰键组合" }
        return AwesunKeyboardShortcut.modifierOptions.map { $0.0 }.filter { modifiers.contains($0) }
            .joined(separator: "+") + " + 选主键"
    }

    private func choose(_ key: AwesunKeySpec) {
        if let modifier = AwesunKeyboardLayout.modifierName(for: key.vk) {
            if modifiers.contains(modifier) { modifiers.remove(modifier) }
            else { modifiers.insert(modifier) }
        } else {
            let chosen = key.vk.hasPrefix("MOUSE_") ? Set<String>() : Set(
                AwesunKeyboardShortcut.modifierOptions.filter { modifiers.contains($0.0) }.map { $0.1 }
            )
            assign(AwesunAccessorySlot(key: key.vk, modifiers: chosen))
        }
    }

    private func assign(_ slot: AwesunAccessorySlot) {
        if let duplicate = slots.firstIndex(where: { $0 == slot }), duplicate != selected {
            slots[duplicate] = slots[selected]
        }
        slots[selected] = slot
        if slots.last.flatMap({ $0 }) != nil { slots.append(nil) }
        modifiers = []
    }
}
