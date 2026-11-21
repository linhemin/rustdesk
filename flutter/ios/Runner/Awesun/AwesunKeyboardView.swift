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

    static let common = [
        Self(labels: ["Ctrl", "Alt", "Del"], key: "secure-attention", modifiers: []),
        Self(labels: ["Alt", "Tab"], key: "VK_TAB", modifiers: ["alt"]),
        Self(labels: ["Win", "D"], key: "VK_D", modifiers: ["meta"]),
        Self(labels: ["Win", "R"], key: "VK_R", modifiers: ["meta"]),
        Self(labels: ["Ctrl", "Shift", "Esc"], key: "VK_ESCAPE", modifiers: ["ctrl", "shift"]),
        Self(labels: ["Ctrl", "A"], key: "VK_A", modifiers: ["ctrl"]),
        Self(labels: ["Ctrl", "C"], key: "VK_C", modifiers: ["ctrl"]),
        Self(labels: ["Ctrl", "V"], key: "VK_V", modifiers: ["ctrl"]),
        Self(labels: ["Ctrl", "X"], key: "VK_X", modifiers: ["ctrl"]),
        Self(labels: ["Ctrl", "Z"], key: "VK_Z", modifiers: ["ctrl"]),
        Self(labels: ["Alt", "F4"], key: "VK_F4", modifiers: ["alt"])
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

struct AwesunKeyboardPanel: View {
    @ObservedObject var model: AwesunSessionModel
    let editing: Bool
    let maxHeight: CGFloat
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    @State private var category = "常用"
    @State private var editingChord = false
    @State private var chordModifiers: Set<String> = []
    @State private var chordKey = "VK_DELETE"

    private var keys: [AwesunKeySpec] {
        switch category {
        case "字母数字": return AwesunKeyboardLayout.selectableKeys.filter {
            $0.label.count == 1 && $0.label.first?.isLetter == true ||
            $0.label.first?.isNumber == true
        }
        case "功能": return AwesunKeyboardLayout.selectableKeys.filter {
            $0.label.dropFirst().allSatisfy(\.isNumber) && $0.label.hasPrefix("F") && $0.label.count > 1
        }
        case "全部": return AwesunKeyboardLayout.selectableKeys
        default: return ["VK_CONTROL", "VK_SHIFT", "VK_MENU", "VK_LWIN",
                         "MOUSE_LEFT", "MOUSE_MIDDLE", "MOUSE_RIGHT", "VK_BACK",
                         "VK_DELETE", "VK_ENTER", "VK_SPACE", "VK_ESCAPE", "VK_TAB",
                         "VK_UP", "VK_LEFT", "VK_DOWN", "VK_RIGHT", "VK_HOME", "VK_END",
                         "VK_PRIOR", "VK_NEXT"].compactMap { AwesunKeyboardLayout.keyByCode[$0] }
        }
    }

    var body: some View {
        AwesunSheetShell(title: editing ? "自定义键盘栏" : "更多按键", onClose: model.closeSheet) {
            ScrollView {
                if editing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已添加到键盘栏")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AwesunPalette.textSecondary)
                        ForEach(model.accessoryKeys, id: \.self) { code in
                            let title = model.customShortcut(for: code)?.title ??
                                AwesunKeyboardLayout.keyByCode[code].map(AwesunKeyboardLayout.title)
                            if let title = title {
                                HStack(spacing: 17) {
                                    Text(title)
                                    Spacer()
                                    reorder("chevron.up", "上移", code, -1)
                                    reorder("chevron.down", "下移", code, 1)
                                    Button { model.removeAccessoryKey(code) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(AwesunPalette.brandRed)
                                    }
                                    .accessibilityLabel("移除按键")
                                }
                                .padding(.horizontal, 8)
                                .frame(minHeight: 36)
                            }
                        }
                        Text("可添加按键")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AwesunPalette.textSecondary)
                    }
                    .padding(.bottom, 8)
                    if editingChord { chordEditor }
                    else {
                        Button { editingChord = true } label: {
                            AwesunActionRow(icon: "command", title: "添加组合键")
                        }
                        .padding(.bottom, 8)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(["常用", "字母数字", "功能", "全部"], id: \.self) { tab in
                        Button {
                            category = tab
                        } label: {
                            Text(tab).font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(category == tab ? AwesunPalette.brandRed : Color.white.opacity(0.08))
                                .cornerRadius(7)
                        }
                    }
                }
                .padding(.bottom, 8)
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(keys) { key in
                        let selected = editing && model.accessoryKeys.contains(key.vk)
                        Button {
                            if editing {
                                model.toggleAccessoryKey(key.vk)
                            } else {
                                model.sendAccessoryKey(key)
                            }
                        } label: {
                            Text(AwesunKeyboardLayout.title(for: key))
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(selected ? AwesunPalette.brandRed : Color.white.opacity(0.10))
                                .cornerRadius(6)
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: maxHeight)
            .padding(.top, 10)
            .foregroundColor(.white)
            .buttonStyle(.plain)
        }
    }

    private var chordEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("添加组合键").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                ForEach(AwesunKeyboardShortcut.modifierOptions.indices, id: \.self) { index in
                    let modifier = AwesunKeyboardShortcut.modifierOptions[index]
                    Button {
                        if chordModifiers.contains(modifier.1) { chordModifiers.remove(modifier.1) }
                        else { chordModifiers.insert(modifier.1) }
                    } label: {
                        Text(modifier.0).font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(chordModifiers.contains(modifier.1) ? AwesunPalette.brandRed : Color.white.opacity(0.10))
                            .cornerRadius(6)
                    }
                }
            }
            HStack {
                Menu {
                    ForEach(AwesunKeyboardLayout.selectableKeys.filter {
                        !$0.isModifier && !$0.vk.hasPrefix("MOUSE_") && $0.vk != "VK_LWIN"
                    }) { key in
                        Button(AwesunKeyboardLayout.title(for: key)) { chordKey = key.vk }
                    }
                } label: {
                    Label(AwesunKeyboardLayout.keyByCode[chordKey].map(AwesunKeyboardLayout.title) ?? "选择按键",
                          systemImage: "chevron.up.chevron.down")
                }
                Spacer()
                Button("取消") { editingChord = false }
                Button("添加") {
                    model.addAccessoryShortcut(modifiers: chordModifiers, key: chordKey)
                    editingChord = false
                    chordModifiers = []
                }
                .foregroundColor(AwesunPalette.brandRed)
                .disabled(chordModifiers.isEmpty)
            }
            .font(.system(size: 13))
            .frame(minHeight: 36)
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(9)
    }

    private func reorder(_ icon: String, _ title: String, _ code: String,
                         _ offset: Int) -> some View {
        Button { model.moveAccessoryKey(code, offset: offset) } label: {
            Image(systemName: icon)
        }
        .accessibilityLabel(Text(title))
    }
}
