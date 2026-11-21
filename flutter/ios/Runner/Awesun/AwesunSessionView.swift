import SwiftUI

struct AwesunSessionView: View {
    @ObservedObject var model: AwesunSessionModel
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.keyboardInset > 0 {
                keyboardAccessory.position(
                    x: size.width / 2, y: size.height - model.keyboardInset - 19
                )
            } else if model.keyboardOpen {
                ScrollView { AwesunKeyboardView(model: model) }
                    .frame(height: AwesunControlLayout.keyboardHeight(in: size))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                controls
                if model.mouseVisible {
                    AwesunVirtualMouseView(model: model, screenSize: size)
                }
            }

            if let toast = model.toast {
                AwesunToastView(toast: toast)
                    .position(x: size.width / 2, y: size.height * 0.28)
                    .allowsHitTesting(false)
            }
            sheetLayer
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "awesunControls")
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    private var controls: some View {
        ZStack {
            control(model.displayLocked ? "lock.fill" : "lock.open", label: "锁定显示") {
                if model.displayLocked {
                    model.setDisplayLocked(false)
                } else {
                    model.sheet = .lock
                }
            }
            .position(AwesunControlLayout.lock(in: size))
            control("keyboard", label: "键盘") { model.systemKeyboard() }
                .position(AwesunControlLayout.rail(0, in: size))
            control("gamecontroller", label: "游戏键盘") { model.sheet = .gamepad }
                .position(AwesunControlLayout.rail(1, in: size))
            control("chevron.up.chevron.down", label: "远程操作", accent: true) {
                model.toggleFunctions()
            }
            .position(AwesunControlLayout.rail(2, in: size))
        }
    }

    private func control(_ symbol: String, label: String, accent: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button {
            model.haptic(.light)
            action()
        } label: {
            Group {
                if symbol == "keyboard" {
                    AwesunKeyboardGlyph()
                } else if accent {
                    AwesunWheelGlyph()
                } else {
                    Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                }
            }
                .foregroundColor(accent ? AwesunPalette.brandRed : .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.78)))
                .contentShape(Circle())
        }
        .buttonStyle(AwesunPressStyle())
        .accessibilityLabel(Text(label))
    }

    private var keyboardAccessory: some View {
        HStack(spacing: 4) {
            accessoryButton("自定义", width: 50) { model.sheet = .keyboardLayout }
            accessoryButton("快捷键", width: 50) { model.sheet = .shortcuts }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.accessoryKeys, id: \.self) { code in
                        if let key = AwesunKeyboardLayout.keyByCode[code] {
                            accessoryButton(AwesunKeyboardLayout.title(for: key),
                                selected: model.modifiers.contains(key.label), width: 38) {
                                model.sendAccessoryKey(key)
                            }
                        }
                    }
                }
            }
            accessoryButton("•••", width: 34) { model.sheet = .keyboardMore }
            accessoryButton("✕", width: 33) { model.systemKeyboard(false) }
        }
        .padding(4)
        .frame(width: size.width, height: 38)
        .background(Color(awesun: 0xFF12111C))
    }

    private func accessoryButton(_ title: String, selected: Bool = false,
                                 width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: width, height: 28)
                .background(selected ? AwesunPalette.brandRed : Color.white.opacity(0.09))
                .cornerRadius(7)
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sheetLayer: some View {
        if model.functionsOpen || model.sheet != nil {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35).onTapGesture { model.closePanel() }
                Group {
                    if model.functionsOpen {
                        AwesunFunctionSheet(model: model)
                    } else {
                        switch model.sheet {
                        case .mode: AwesunModeSheet(model: model)
                        case .lock: AwesunLockSheet(model: model)
                        case .guide: AwesunGuideSheet(model: model)
                        case .actions: AwesunActionPanel(model: model, height: panelHeight)
                        case .displaySettings: AwesunDisplayPanel(model: model, height: panelHeight)
                        case .keyboardMore:
                            AwesunKeyboardPanel(model: model, editing: false, maxHeight: panelHeight)
                        case .keyboardLayout:
                            AwesunKeyboardPanel(model: model, editing: true, maxHeight: panelHeight)
                        case .gamepad: AwesunGamePanel(model: model)

                        case .displays: actionSheet(
                            "切换屏幕", (0..<model.displayCount).map {
                                "屏幕 \($0 + 1)" + ($0 == model.selectedDisplay ? "   ✓" : "")
                            }
                        ) { index in
                            model.selectDisplay(index)
                        }
                        case .shortcuts: AwesunShortcutPanel(model: model, height: panelHeight)
                        case .none: EmptyView()
                        }
                    }
                }
                .padding(.bottom, model.keyboardInset)
            }
        }
    }

    private var panelHeight: CGFloat {
        max(80, min(size.height * 0.55, size.height - model.keyboardInset - 110))
    }

    private func actionSheet(_ title: String, _ items: [String],
                             choose: @escaping (Int) -> Void) -> some View {
        AwesunSheetShell(title: title, onClose: model.closeSheet) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                        Button {
                            choose(index)
                        } label: {
                            Text(title)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        Divider().background(AwesunPalette.hairline)
                    }
                }
            }
            .frame(maxHeight: size.height * 0.55)
        }
    }
}

enum AwesunControlLayout {
    static let hub: CGFloat = 31
    static let arcRadius: CGFloat = 61
    static let arcWidth: CGFloat = 29
    static let arcSpan: Double = 37
    static let wheelOffset: CGFloat = 59
    static let wheelRadius: CGFloat = 14
    static let closeOffset = CGSize(width: 70, height: -70)
    static let ringRadius: CGFloat = 60
    static let ringThickness: CGFloat = 28
    static let mouseSize: CGFloat = 178

    static func keyboardHeight(in size: CGSize) -> CGFloat {
        min(391, size.height * 0.65)
    }

    static func lock(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - 34, y: max(41, size.height * 0.099))
    }

    static func rail(_ index: Int, in size: CGSize) -> CGPoint {
        let bottom = min(size.height - 29, size.height * 0.933)
        let spacing = min(49, size.height * 0.057)
        return CGPoint(x: size.width - 34, y: bottom - CGFloat(2 - index) * spacing)
    }

    static func mouseCenter(_ anchor: CGPoint, in size: CGSize) -> CGPoint {
        let pad: CGFloat = 1
        let start = anchor == .zero
            ? CGPoint(x: size.width * 0.587, y: size.height * 0.469)
            : anchor
        return CGPoint(x: min(max(pad, start.x), max(pad, size.width - pad)),
                       y: min(max(pad, start.y), max(pad, size.height - pad)))
    }

    static func dockCenter(_ model: AwesunSessionModel, in size: CGSize) -> CGPoint {
        let anchor = model.collapsedMouseAnchor == .zero
            ? mouseCenter(model.mouseAnchor, in: size)
            : model.collapsedMouseAnchor
        let end = max(51, rail(0, in: size).y - 49)
        return CGPoint(x: size.width - 29, y: min(end, max(50, anchor.y)))
    }

    static func circle(_ point: CGPoint, at center: CGPoint, radius: CGFloat) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= radius
    }

    static func mouseHit(_ point: CGPoint, model: AwesunSessionModel, size: CGSize) -> Bool {
        let center = mouseCenter(model.mouseAnchor, in: size)
        if model.mouseCollapsed {
            return circle(point, at: dockCenter(model, in: size), radius: 20)
        }
        let local = CGPoint(x: point.x - center.x, y: point.y - center.y)
        if model.wheelOpen {
            return abs(hypot(local.x, local.y) - ringRadius) <= ringThickness / 2 ||
                circle(local, at: CGPoint(x: closeOffset.width, y: closeOffset.height), radius: 13)
        }
        if circle(local, at: .zero, radius: hub) ||
            circle(local, at: CGPoint(x: 0, y: -wheelOffset), radius: wheelRadius) ||
            circle(local, at: CGPoint(x: 0, y: wheelOffset), radius: wheelRadius) ||
            circle(local, at: CGPoint(x: closeOffset.width, y: closeOffset.height), radius: 13) {
            return true
        }
        let half = mouseSize / 2
        let rect = CGRect(x: 0, y: 0, width: mouseSize, height: mouseSize)
        let p = CGPoint(x: local.x + half, y: local.y + half)
        return [-180.0, 0.0].contains { angle in
            AwesunArcBand(centerDeg: angle, spanDeg: arcSpan, radius: arcRadius,
                          thickness: arcWidth).path(in: rect).contains(p)
        }
    }
}

struct AwesunVirtualMouseView: View {
    @ObservedObject var model: AwesunSessionModel
    let screenSize: CGSize
    @State private var lastTranslation: CGSize = .zero
    @GestureState private var hubDragging = false

    var body: some View {
        let center = model.mouseCollapsed
            ? AwesunControlLayout.dockCenter(model, in: screenSize)
            : AwesunControlLayout.mouseCenter(model.mouseAnchor, in: screenSize)
        ZStack {
            if model.mouseCollapsed {
                Button {
                    model.haptic(.light)
                    model.expandMouse(at: AwesunControlLayout.mouseCenter(model.mouseAnchor, in: screenSize))
                } label: {
                    Image(AwesunIcons.mouse)
                        .renderingMode(.template)
                        .resizable().scaledToFit()
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.black.opacity(0.78)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开虚拟鼠标")
            } else {
                if model.wheelOpen {
                    AwesunScrollRing(model: model)
                } else {
                    arc(center: -180, secondary: true)
                    arc(center: 0, secondary: false)
                    hub
                    smallButton(offset: AwesunControlLayout.wheelOffset, label: "滚轮向下", lines: 5) {
                        model.scroll(-1)
                        model.refreshMouseIdleTimer()
                    }
                }
                AwesunWheelTrigger(model: model, center: center)
                    .offset(y: -AwesunControlLayout.wheelOffset)
                Button {
                    if model.wheelOpen {
                        model.wheelOpen = false
                        model.refreshMouseIdleTimer()
                    } else {
                        model.collapseMouse()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .background(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(AwesunControlLayout.closeOffset)
                .accessibilityLabel(model.wheelOpen ? "退出圆形滚轮" : "收起虚拟鼠标")
            }
        }
        .frame(width: AwesunControlLayout.mouseSize, height: AwesunControlLayout.mouseSize)
        .position(center)
        .animation(.easeOut(duration: 0.18), value: model.mouseCollapsed)
        .onAppear {
            if !model.mouseCollapsed { syncPointer() }
            model.refreshMouseIdleTimer()
        }
        .onDisappear {
            model.endDrag()
            model.mouseGesture(false)
            model.pauseMouseIdleTimer()
        }
    }

    private func arc(center: Double, secondary: Bool) -> some View {
        let band = AwesunArcBand(centerDeg: center, spanDeg: AwesunControlLayout.arcSpan,
                                 radius: AwesunControlLayout.arcRadius,
                                 thickness: AwesunControlLayout.arcWidth)
        return AwesunMouseBand(model: model, band: band, secondary: secondary,
                               sync: syncPointer, move: move)
    }

    private var hub: some View {
        Circle()
            .fill(model.dragging || hubDragging ? AwesunPalette.brandRed : AwesunPalette.mouseFill)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.68), lineWidth: 2))
            .frame(width: AwesunControlLayout.hub * 2, height: AwesunControlLayout.hub * 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("awesunControls"))
                    .updating($hubDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        move(CGSize(width: value.translation.width - lastTranslation.width,
                                    height: value.translation.height - lastTranslation.height))
                        lastTranslation = value.translation
                    }
                    .onEnded { _ in lastTranslation = .zero }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { model.collapseMouse() }
                    .exclusively(before: TapGesture().onEnded {
                        syncPointer()
                        model.click()
                    })
            )
            .onChange(of: hubDragging) { value in
                model.mouseGesture(value)
                if !value { lastTranslation = .zero }
            }
            .accessibilityLabel("移动光标")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { syncPointer(); model.click() }
    }

    private func syncPointer() {
        model.moveVirtualPointer(to: AwesunControlLayout.mouseCenter(model.mouseAnchor, in: screenSize))
    }

    private func move(_ delta: CGSize) {
        let current = AwesunControlLayout.mouseCenter(model.mouseAnchor, in: screenSize)
        let next = CGPoint(x: current.x + delta.width, y: current.y + delta.height)
        model.moveVirtualPointer(to: AwesunControlLayout.mouseCenter(next, in: screenSize))
    }

    private func smallButton(offset: CGFloat, label: String, lines: Int,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(AwesunPalette.mouseFill)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.68), lineWidth: 2))
                .overlay {
                    VStack(spacing: 2) {
                        ForEach(0..<lines, id: \.self) { _ in
                            Capsule().fill(.black.opacity(0.30)).frame(width: 13, height: 1.5)
                        }
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .offset(y: offset)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct AwesunMouseBand: View {
    @ObservedObject var model: AwesunSessionModel
    let band: AwesunArcBand
    let secondary: Bool
    let sync: () -> Void
    let move: (CGSize) -> Void

    @GestureState private var down = false
    @State private var lastTranslation: CGSize = .zero
    @State private var didDrag = false

    var body: some View {
        band.fill(down ? AwesunPalette.brandRed : AwesunPalette.mouseFill)
            .overlay(band.stroke(Color.black.opacity(0.72), lineWidth: 2))
            .frame(width: AwesunControlLayout.mouseSize, height: AwesunControlLayout.mouseSize)
            .contentShape(band)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("awesunControls"))
                    .updating($down) { _, state, _ in state = true }
                    .onChanged { value in
                        guard !secondary else { return }
                        let translation = value.translation
                        if !didDrag {
                            guard hypot(translation.width, translation.height) >= 5 else { return }
                            didDrag = true
                            sync()
                            model.beginDrag()
                        }
                        move(CGSize(width: translation.width - lastTranslation.width,
                                    height: translation.height - lastTranslation.height))
                        lastTranslation = translation
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if didDrag {
                            model.endDrag()
                        } else if distance < 5 {
                            sync()
                            model.click(secondary ? "right" : "left")
                        }
                        reset()
                    }
            )
            .onChange(of: down) { value in
                model.mouseGesture(value)
                if !value {
                    if didDrag { model.endDrag() }
                    reset()
                }
            }
            .onDisappear { reset(); model.endDrag() }
            .accessibilityLabel(secondary ? "鼠标右键" : "鼠标左键及拖动")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { sync(); model.click(secondary ? "right" : "left") }
    }

    private func reset() {
        lastTranslation = .zero
        didDrag = false
    }
}

struct AwesunAnnulus: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = AwesunControlLayout.ringRadius
        let half = AwesunControlLayout.ringThickness / 2
        func circle(_ r: CGFloat) -> CGRect {
            CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)
        }
        var path = Path(ellipseIn: circle(radius + half))
        path.addEllipse(in: circle(radius - half))
        return path
    }
}

struct AwesunScrollRing: View {
    @ObservedObject var model: AwesunSessionModel
    @State private var last: Double?
    @State private var remainder = 0.0
    @State private var indicator: Double?
    @GestureState private var scrolling = false
    private let step = Double.pi / 12

    var body: some View {
        let center = AwesunControlLayout.mouseSize / 2
        AwesunAnnulus()
            .fill(Color.white.opacity(0.27), style: FillStyle(eoFill: true))
            .overlay(AwesunAnnulus().stroke(Color.black.opacity(0.68), lineWidth: 2))
            .overlay {
                if let angle = indicator {
                    Circle().fill(Color(awesun: 0xFFF4BA58))
                        .frame(width: 23, height: 23)
                        .blur(radius: 2)
                        .offset(x: AwesunControlLayout.ringRadius * cos(angle),
                                y: AwesunControlLayout.ringRadius * sin(angle))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: center * 2, height: center * 2)
            .contentShape(AwesunAnnulus(), eoFill: true)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($scrolling) { _, state, _ in state = true }
                    .onChanged { value in
                        let dx = value.location.x - center
                        let dy = value.location.y - center
                        guard hypot(dx, dy) > AwesunControlLayout.ringRadius / 2 else {
                            last = nil
                            return
                        }
                        let angle = atan2(dy, dx)
                        if let previous = last {
                            let delta = angle - previous
                            remainder += atan2(sin(delta), cos(delta))
                            let ticks = Int(remainder / step)
                            if ticks != 0 {
                                model.scroll(-ticks)
                                remainder -= Double(ticks) * step
                            }
                        }
                        last = angle
                        indicator = angle
                    }
                    .onEnded { _ in reset() }
            )
            .onChange(of: scrolling) { value in
                model.mouseGesture(value)
                if !value { reset() }
            }
            .accessibilityLabel("圆形滚轮")
            .accessibilityAdjustableAction { direction in
                if direction == .increment { model.scroll(-1) }
                if direction == .decrement { model.scroll(1) }
            }
    }

    private func reset() {
        last = nil
        remainder = 0
        indicator = nil
    }
}

struct AwesunToastView: View {
    let toast: AwesunToastItem

    var body: some View {
        Text(toast.text)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.62)))
    }
}

struct AwesunPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct AwesunWheelTrigger: View {
    @ObservedObject var model: AwesunSessionModel
    let center: CGPoint
    @GestureState private var contact = false
    @State private var started = false
    @State private var holding = false
    @State private var timer: Task<Void, Never>?
    @State private var lastAngle: Double?
    @State private var angularRemainder = 0.0
    private let tickAngle = Double.pi / 12

    var body: some View {
        Circle()
            .fill(AwesunPalette.mouseFill)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.68), lineWidth: 2))
            .frame(width: 28, height: 28)
            .opacity(model.wheelOpen ? 0.001 : 1)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("awesunControls"))
                    .updating($contact) { _, state, _ in state = true }
                    .onChanged { value in
                        if !started {
                            started = true
                            model.mouseGesture(true)
                            timer = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 220_000_000)
                                guard !Task.isCancelled else { return }
                                holding = true
                                model.haptic(.light)
                                model.openWheel()
                            }
                        }
                        if holding {
                            let delta = CGPoint(x: value.location.x - center.x,
                                                y: value.location.y - center.y)
                            guard hypot(delta.x, delta.y) > 30 else { lastAngle = nil; return }
                            let angle = atan2(Double(delta.y), Double(delta.x))
                            if let previous = lastAngle {
                                angularRemainder += atan2(sin(angle - previous), cos(angle - previous))
                                let ticks = Int(angularRemainder / tickAngle)
                                if ticks != 0 {
                                    model.scroll(-ticks)
                                    angularRemainder -= Double(ticks) * tickAngle
                                }
                            }
                            lastAngle = angle
                        } else if hypot(value.translation.width, value.translation.height) > 12 {
                            timer?.cancel()
                        }
                    }
                    .onEnded { value in
                        if !holding && hypot(value.translation.width, value.translation.height) < 8 {
                            model.scroll(1)
                        }
                        finish()
                    }
            )
            .allowsHitTesting(!model.wheelOpen || holding)
            .onChange(of: contact) { value in if !value { finish() } }
            .onDisappear { finish() }
            .accessibilityLabel("长按打开圆形滚轮")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.openWheel() }
    }

    private func finish() {
        timer?.cancel()
        timer = nil
        started = false
        holding = false
        lastAngle = nil
        angularRemainder = 0
        model.mouseGesture(false)
    }
}
