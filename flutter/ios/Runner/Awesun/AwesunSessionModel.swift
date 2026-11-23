import SwiftUI

enum AwesunMode {
    case pointer
    case touch

    var title: String {
        switch self {
        case .pointer: return "指针模式"
        case .touch: return "触控模式"
        }
    }
}

enum AwesunSheetKind: Equatable {
    case mode, lock, guide, actions, displays, shortcuts, displaySettings, keyboardMore, keyboardLayout, keyboardFull, gamepad
}

struct AwesunToastItem: Equatable {
    let id = UUID()
    let text: String
}

struct AwesunFunctionItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    var symbol = false
}

final class AwesunSessionModel: ObservableObject {
    @Published var active = false
    @Published var keyboardInset: CGFloat = 0
    @Published private(set) var keyboardPanelHeight: CGFloat = 0
    @Published var mode: AwesunMode = .pointer
    @Published var soundOn = true
    @Published var displayLocked = false
    private static let mouseVisibleKey = "awesun.mouse.enabled"
    private static let mousePlacementKey = "awesun.mouse.placement"
    @Published private(set) var mouseVisible = UserDefaults.standard.bool(forKey: AwesunSessionModel.mouseVisibleKey)
    @Published private(set) var mouseCollapsed = true
    @Published var mouseAnchor: CGPoint?
    @Published var videoViewport: CGRect?
    @Published var holdsMouseInScreenSpace = false
    var mouseViewport: CGRect? { holdsMouseInScreenSpace ? nil : videoViewport }
    @Published var pressedMouseRegion: AwesunMouseRegion?
    @Published var wheelIndicator: Double?
    @Published var lockPlacement = AwesunDockPlacement(fraction: 0.10)
    @Published var mousePlacement = AwesunSessionModel.loadMousePlacement() {
        didSet {
            if let data = try? JSONEncoder().encode(mousePlacement) {
                UserDefaults.standard.set(data, forKey: Self.mousePlacementKey)
            }
        }
    }
    @Published var wheelOpen = false
    @Published private(set) var dragging = false
    private var restoreSystemKeyboard = false
    @Published var modifiers: Set<String> = []
    @Published var pressedKeycap = ""
    @Published var functionsOpen = false
    @Published var sheet: AwesunSheetKind?
    @Published var actions: [String] = []
    @Published var displayOptions: [AwesunDisplayOption] = []
    @Published private(set) var performance = AwesunPerformanceStatus()
    @Published var accessoryKeys = AwesunKeyboardLayout.savedAccessoryKeys()
    @Published var accessoryShortcuts = AwesunKeyboardShortcut.saved()
    @Published var displayCount = 0
    @Published var selectedDisplay = 0
    @Published var qualityVisible = false
    @Published var toast: AwesunToastItem?

    private var canInput = false
    private var canSwitchMode = false
    private var canSound = false
    private var canScreenshot = false
    private var toastTask: Task<Void, Never>?
    private var mouseIdleTask: Task<Void, Never>?
    private var mouseGestureInProgress = false
    private var menuRevision = 0

    @Published private var functionOrder = [
        "quit", "mouse", "kbd", "mode", "lock", "guide", "shot", "sound", "screen",
        "display", "quality", "chat", "fullKeyboard", "layout", "keys", "game", "actions"
    ]

    var functions: [AwesunFunctionItem] {
        let items = [
            AwesunFunctionItem(id: "mouse", title: "虚拟鼠标", icon: AwesunIcons.mouse),
            AwesunFunctionItem(id: "kbd", title: "系统键盘", icon: AwesunIcons.keyboard),
            AwesunFunctionItem(id: "fullKeyboard", title: "虚拟键盘", icon: "keyboard", symbol: true),
            AwesunFunctionItem(id: "mode", title: "手机模式", icon: AwesunIcons.touch),
            AwesunFunctionItem(id: "lock", title: "锁定显示", icon: AwesunIcons.lock),
            AwesunFunctionItem(id: "guide", title: "手势指南", icon: AwesunIcons.guide),
            AwesunFunctionItem(id: "shot", title: "截图", icon: AwesunIcons.shot),
            AwesunFunctionItem(id: "sound", title: "声音", icon: soundOn ? AwesunIcons.soundOn : AwesunIcons.soundOff),
            AwesunFunctionItem(id: "screen", title: "切换屏幕", icon: AwesunIcons.switchScreen),
            AwesunFunctionItem(id: "display", title: "显示设置", icon: "display", symbol: true),
            AwesunFunctionItem(id: "quality", title: qualityVisible ? "关闭品质检测" : "品质检测", icon: "waveform.path", symbol: true),
            AwesunFunctionItem(id: "chat", title: "聊天", icon: "message", symbol: true),
            AwesunFunctionItem(id: "layout", title: "自定义键盘", icon: "keyboard.badge.ellipsis", symbol: true),
            AwesunFunctionItem(id: "keys", title: "更多按键", icon: "ellipsis", symbol: true),
            AwesunFunctionItem(id: "game", title: "游戏键盘", icon: "gamecontroller", symbol: true),
            AwesunFunctionItem(id: "actions", title: "更多操作", icon: AwesunIcons.more),
            AwesunFunctionItem(id: "quit", title: "断开", icon: AwesunIcons.quit)
        ]
        return functionOrder.compactMap { id in
            if !canInput && ["mouse", "kbd", "fullKeyboard", "keys", "layout", "game"].contains(id) { return nil }
            switch id {
            case "mode" where !canSwitchMode: return nil
            case "sound" where !canSound: return nil
            case "shot" where !canScreenshot: return nil
            case "screen" where displayCount < 2: return nil
            case "actions" where actions.isEmpty: return nil
            default: return items.first { $0.id == id }
            }
        }
    }

    func moveFunction(from: Int, to: Int) {
        let visible = functions
        guard visible.indices.contains(from), visible.indices.contains(to),
              let fromIndex = functionOrder.firstIndex(of: visible[from].id),
              let toIndex = functionOrder.firstIndex(of: visible[to].id) else { return }
        functionOrder.swapAt(fromIndex, toIndex)
    }

    func toggleFunctions() {
        if functionsOpen { closePanel() } else { openFunctions() }
    }

    func openFunctions() {
        endDrag()
        menuRevision += 1
        let revision = menuRevision
        closeSheet()
        functionsOpen = true
        AwesunBridge.shared.command("menu") { [weak self] response in
            guard let self = self, self.active, self.functionsOpen,
                  self.menuRevision == revision, let values = response as? [String: Any] else { return }
            self.configure(values)
        }
    }

    func configure(_ values: [String: Any]) {
        if let touch = values["touch"] as? Bool {
            mode = touch ? .touch : .pointer
        }
        if let locked = values["locked"] as? Bool { displayLocked = locked }
        if let allowed = values["canInput"] as? Bool { canInput = allowed }
        if let allowed = values["canSwitchMode"] as? Bool { canSwitchMode = allowed }
        if let allowed = values["canSound"] as? Bool { canSound = allowed }
        if let enabled = values["sound"] as? Bool { soundOn = enabled }
        if let allowed = values["screenshot"] as? Bool { canScreenshot = allowed }
        if let count = values["displays"] as? Int { displayCount = count }
        if let selection = values["selectedDisplay"] as? Int { selectedDisplay = selection }
        if let quality = values["quality"] as? Bool { qualityVisible = quality }
        if let labels = values["actions"] as? [String] { actions = labels }
    }

    func closeFunctions() {
        functionsOpen = false
    }

    func closeSheet() {
        let reopen = restoreSystemKeyboard
        restoreSystemKeyboard = false
        if isKeyboardPanel { releaseModifiers() }
        sheet = nil
        setKeyboardPanelHeight(0)
        if reopen { systemKeyboard() }
    }

    func closeObscuredPanels() {
        restoreSystemKeyboard = false
        closePanel()
    }

    var isKeyboardPanel: Bool {
        sheet == .keyboardMore || sheet == .keyboardLayout || sheet == .keyboardFull || sheet == .shortcuts
    }

    var mouseObstruction: CGFloat {
        keyboardInset > 0 ? keyboardInset + 38 : (isKeyboardPanel ? keyboardPanelHeight : 0)
    }

    func keepVirtualMouseReachable(in size: CGSize) {
        guard mouseVisible && !mouseCollapsed else { return }
        let center = AwesunControlLayout.mouseGeometry(mouseAnchor, in: size, viewport: mouseViewport,
                                                        obstruction: mouseObstruction).center
        if mouseAnchor != center { mouseAnchor = center }
    }

    func setKeyboardPanelHeight(_ height: CGFloat) {
        let height = isKeyboardPanel && height.isFinite ? max(0, height) : 0
        guard keyboardPanelHeight != height else { return }
        keyboardPanelHeight = height
        AwesunBridge.shared.command("keyboardPanelHeight", ["height": Double(height)])
    }

    func openKeyboardPanel(_ panel: AwesunSheetKind) {
        let wasVisible = keyboardInset > 0
        restoreSystemKeyboard = restoreSystemKeyboard || wasVisible
        sheet = panel
        if wasVisible { systemKeyboard(false) }
    }

    func dismissRemoteKeyboard() {
        restoreSystemKeyboard = false
        closePanel()
        systemKeyboard(false)
    }

    func showSystemKeyboardFromDeck() {
        restoreSystemKeyboard = false
        closeSheet()
        systemKeyboard()
    }

    func closePanel() {
        closeFunctions()
        closeSheet()
    }

    func perform(_ item: AwesunFunctionItem) {
        closeFunctions()
        switch item.id {
        case "mouse":
            setMouseVisible(!mouseVisible)
        case "kbd":
            systemKeyboard()
        case "keys":
            openKeyboardPanel(.keyboardMore)
        case "fullKeyboard":
            openKeyboardPanel(.keyboardFull)
        case "layout":
            openKeyboardPanel(.keyboardLayout)
        case "game": sheet = .gamepad
        case "mode": sheet = .mode
        case "lock": sheet = .lock
        case "guide": sheet = .guide
        case "actions": sheet = .actions
        case "screen": sheet = .displays
        case "sound":
            AwesunBridge.shared.command("sound") { [weak self] response in
                if let enabled = response as? Bool { self?.soundOn = enabled }
            }
        case "display":
            sheet = .displaySettings
            loadDisplayOptions()
        case "shot":
            takeScreenshot()
        case "chat", "quality":
            AwesunBridge.shared.command(item.id)
        case "quit":
            AwesunBridge.shared.closeSession()
        default: break
        }
    }

    private func loadDisplayOptions() {
        AwesunBridge.shared.command("display") { [weak self] response in
            guard let self = self, self.sheet == .displaySettings,
                  let values = response as? [[String: Any]] else { return }
            self.displayOptions = values.compactMap(AwesunDisplayOption.init)
        }
    }

    func selectDisplayOption(_ index: Int) {
        if let option = displayOptions.first(where: { $0.id == index }) {
            if option.group == "显示选项" || option.group == "虚拟显示器" {
                if let current = displayOptions.firstIndex(where: { $0.id == index }) {
                    displayOptions[current].selected.toggle()
                }
            } else {
                for current in displayOptions.indices where displayOptions[current].group == option.group {
                    displayOptions[current].selected = displayOptions[current].id == index
                }
            }
        }
        AwesunBridge.shared.command("displayAction", ["index": index])
    }

    func updatePerformance(_ values: [String: Any]) {
        performance = AwesunPerformanceStatus(
            supported: values["supported"] as? Bool == true,
            enabled: values["enabled"] as? Bool == true,
            target: values["target"] as? Int ?? 60,
            effective: values["effective"] as? Int,
            gpuEncode: values["gpuEncode"] as? Bool,
            gpuDecode: values["gpuDecode"] as? Bool == true,
            measuredFps: values["fps"] as? String
        )
    }

    func setPerformance(_ enabled: Bool) {
        AwesunBridge.shared.command("performance", ["enabled": enabled])
    }

    func setPerformanceTarget(_ fps: Int) {
        AwesunBridge.shared.command("performanceTarget", ["fps": fps])
    }

    private func takeScreenshot() {
        AwesunBridge.shared.command("shot") { [weak self] response in
            let messages = [
                "saved": "截图已保存到相册",
                "permissionDenied": "请在 iPhone 设置中允许添加照片",
                "noFrame": "远端画面尚未就绪",
                "encodeFailed": "无法创建截图",
                "saveFailed": "无法将截图保存到相册"
            ]
            if let status = response as? String, let text = messages[status] {
                self?.showToast(text)
            }
        }
    }

    func chooseAction(_ index: Int) {
        closePanel()
        AwesunBridge.shared.command("action", ["index": index])
    }

    func selectDisplay(_ index: Int) {
        closePanel()
        AwesunBridge.shared.command("screen", ["index": index])
    }

    func selectMode(_ next: AwesunMode) {
        AwesunBridge.shared.command("mode", ["touch": next == .touch]) { [weak self] response in
            guard let touch = response as? Bool else { return }
            self?.mode = touch ? .touch : .pointer
            self?.showToast(touch ? "触控模式" : "指针模式")
        }
    }

    func setDisplayLocked(_ locked: Bool) {
        AwesunBridge.shared.command("lock", ["locked": locked]) { [weak self] response in
            guard let locked = response as? Bool else { return }
            self?.displayLocked = locked
            self?.showToast(locked ? "显示已锁定" : "显示已解锁")
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = AwesunToastItem(text: text)
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private static func loadMousePlacement() -> AwesunDockPlacement {
        if let data = UserDefaults.standard.data(forKey: mousePlacementKey),
           let placement = try? JSONDecoder().decode(AwesunDockPlacement.self, from: data),
           (0...1).contains(placement.fraction) {
            return placement
        }
        return AwesunDockPlacement(fraction: 0.47)
    }

    func setMouseVisible(_ shown: Bool) {
        guard mouseVisible != shown else { return }
        UserDefaults.standard.set(shown, forKey: Self.mouseVisibleKey)
        mouseVisible = shown
        collapseMouse()
    }

    func collapseMouse() {
        endDrag()
        pauseMouseIdleTimer()
        mouseCollapsed = true
        wheelOpen = false
        AwesunBridge.shared.pointerVisible(false)
    }

    func expandMouse() {
        mouseCollapsed = false
        wheelOpen = false
        AwesunBridge.shared.pointerVisible(true)
        refreshMouseIdleTimer()
    }

    func openWheel() {
        endDrag()
        wheelOpen = true
        refreshMouseIdleTimer()
    }

    func closeWheelOrMouse() {
        if wheelOpen {
            wheelOpen = false
            refreshMouseIdleTimer()
        } else {
            collapseMouse()
        }
    }

    func pauseMouseIdleTimer() {
        mouseIdleTask?.cancel()
        mouseIdleTask = nil
    }

    func mouseGesture(_ inProgress: Bool) {
        mouseGestureInProgress = inProgress
        refreshMouseIdleTimer()
    }

    func refreshMouseIdleTimer() {
        pauseMouseIdleTimer()
        guard active && mouseVisible && !mouseCollapsed && !mouseGestureInProgress else { return }
        mouseIdleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled { self?.collapseMouse() }
        }
    }

    func moveVirtualPointer(anchor: CGPoint, point: CGPoint) {
        mouseAnchor = anchor
        AwesunBridge.shared.virtualMove(to: point)
    }

    func click(_ button: String = "left", at point: CGPoint? = nil) {
        refreshMouseIdleTimer()
        haptic()
        AwesunBridge.shared.virtualClick(button, at: point)
    }

    func scroll(_ steps: Int, at point: CGPoint? = nil) {
        AwesunBridge.shared.scroll(steps, at: point)
    }

    func beginDrag(at point: CGPoint) {
        guard !dragging else { return }
        dragging = true
        AwesunBridge.shared.virtualDrag(true, at: point)
    }

    func endDrag() {
        guard dragging else { return }
        dragging = false
        AwesunBridge.shared.virtualDrag(false)
    }

    func systemKeyboard(_ visible: Bool = true) {
        if visible { endDrag() }
        releaseModifiers()
        AwesunBridge.shared.command("keyboard", ["visible": visible])
    }

    func toggleModifier(_ name: String) {
        let value: String
        switch name {
        case "Ctrl": value = "ctrl"
        case "Shift": value = "shift"
        case "Alt": value = "alt"
        case "Win": value = "meta"
        default: return
        }
        let down = !modifiers.contains(name)
        if down { modifiers.insert(name) } else { modifiers.remove(name) }
        AwesunBridge.shared.command("modifier", ["name": value, "down": down])
    }

    func releaseModifiers() {
        if modifiers.remove("Caps") != nil {
            AwesunBridge.shared.key("VK_CAPITAL", down: false)
        }
        guard !modifiers.isEmpty else { return }
        modifiers.removeAll()
        AwesunBridge.shared.command("releaseModifiers")
    }

    func sendShortcut(_ shortcut: AwesunKeyboardShortcut) {
        AwesunBridge.shared.command("shortcut", ["key": shortcut.key, "modifiers": shortcut.modifiers])
    }

    func sendAccessoryKey(_ key: AwesunKeySpec) {
        if let modifier = AwesunKeyboardLayout.modifierName(for: key.vk) {
            toggleModifier(modifier)
        } else {
            pressKey(key)
        }
    }

    func customShortcut(for id: String) -> AwesunKeyboardShortcut? {
        accessoryShortcuts.first { $0.id == id }
    }

    var editableAccessorySlots: [AwesunAccessorySlot] {
        accessoryKeys.compactMap { code in
            if let shortcut = customShortcut(for: code) {
                if shortcut.key == "secure-attention" {
                    return AwesunAccessorySlot(key: "VK_DELETE", modifiers: ["ctrl", "alt"])
                }
                return AwesunAccessorySlot(key: shortcut.key, modifiers: Set(shortcut.modifiers))
            }
            guard AwesunKeyboardLayout.keyByCode[code] != nil else { return nil }
            return AwesunAccessorySlot(key: code)
        }
    }

    func replaceAccessorySlots(_ slots: [AwesunAccessorySlot]) {
        var chords: [AwesunKeyboardShortcut] = []
        let keys = slots.map { slot in
            if slot.modifiers.isEmpty { return slot.key }
            let shortcut = slot.shortcut
            chords.append(shortcut)
            return shortcut.id
        }
        accessoryShortcuts = chords
        accessoryKeys = keys
        saveAccessoryKeys()
    }

    private func saveAccessoryKeys() {
        if let data = try? JSONEncoder().encode(accessoryShortcuts) {
            UserDefaults.standard.set(data, forKey: AwesunKeyboardShortcut.storageKey)
        }
        UserDefaults.standard.set(accessoryKeys, forKey: AwesunKeyboardLayout.accessoryStorage)
    }

    func pressKey(_ spec: AwesunKeySpec) {
        pressedKeycap = spec.label
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            if pressedKeycap == spec.label { pressedKeycap = "" }
        }
        haptic()

        if ["Ctrl", "Shift", "Alt", "Win"].contains(spec.label) {
            toggleModifier(spec.label)
            return
        }
        switch spec.vk {
        case "MOUSE_LEFT": click()
        case "MOUSE_MIDDLE": click("middle")
        case "MOUSE_RIGHT": click("right")
        default:
            AwesunBridge.shared.key(spec.vk, down: true)
            AwesunBridge.shared.key(spec.vk, down: false)
        }
    }
}

struct AwesunDisplayOption: Identifiable {
    let id: Int
    let group: String
    let title: String
    var selected: Bool

    init?(_ values: [String: Any]) {
        guard let id = values["index"] as? Int, let group = values["group"] as? String,
              let title = values["title"] as? String else { return nil }
        self.id = id
        self.group = group
        self.title = title
        self.selected = values["selected"] as? Bool == true
    }
}

struct AwesunPerformanceStatus {
    var supported = false
    var enabled = false
    var target = 60
    var effective: Int?
    var gpuEncode: Bool?
    var gpuDecode = false
    var measuredFps: String?
}
