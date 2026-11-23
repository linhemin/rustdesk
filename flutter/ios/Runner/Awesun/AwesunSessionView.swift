import SwiftUI

struct AwesunSessionView: View {
    @ObservedObject var model: AwesunSessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGSize

    private var panelAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.mouseVisible && model.sheet != .gamepad && model.sheet != .guide && !model.functionsOpen {
                AwesunVirtualMouseView(model: model, screenSize: size)
            }
            sessionControls
                .zIndex(model.sheet == .gamepad && !model.functionsOpen ? 1 : 0)
                .animation(panelAnimation, value: model.keyboardInset > 0)
                .animation(panelAnimation, value: model.isKeyboardPanel)

            if let toast = model.toast {
                AwesunToastView(toast: toast)
                    .position(x: size.width / 2, y: size.height * 0.28)
                    .allowsHitTesting(false)
            }
            sheetLayer
                .animation(panelAnimation, value: model.sheet)
                .animation(panelAnimation, value: model.functionsOpen)
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "awesunControls")
        .onPreferenceChange(AwesunKeyboardPanelSize.self) { height in
            let before = model.mouseObstruction
            model.setKeyboardPanelHeight(height)
            if model.mouseObstruction > before { model.keepVirtualMouseReachable(in: size) }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    @ViewBuilder
    private var sessionControls: some View {
        if model.keyboardInset == 0 && !model.isKeyboardPanel {
            controls.transition(.opacity)
        }
    }

    @ViewBuilder
    private var controls: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer { floatingControls }
        } else {
            floatingControls
        }
#else
        floatingControls
#endif
    }

    private var floatingControls: some View {
        ZStack {
            AwesunDockButton(placement: $model.lockPlacement, size: size,
                             label: model.displayLocked ? "解除锁定" : "锁定显示",
                             tap: {
                if model.displayLocked {
                    model.setDisplayLocked(false)
                } else {
                    model.sheet = .lock
                }
            }) {
                Image(systemName: model.displayLocked ? "lock.fill" : "lock.open")
                    .resizable().scaledToFit()
            }
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
                    Image(systemName: symbol).resizable().scaledToFit()
                }
            }
                .modifier(AwesunFloatingChrome(accent: accent))
        }
        .buttonStyle(AwesunPressStyle())
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private var sheetLayer: some View {
        if model.functionsOpen || (model.sheet != nil &&
            !(model.isKeyboardPanel && model.keyboardInset > 0)) {
            ZStack(alignment: .bottom) {
                if model.isKeyboardPanel {
                    Color.clear.allowsHitTesting(false)
                } else {
                    Color.black.opacity(model.sheet == .gamepad ? 0 : 0.45)
                        .contentShape(Rectangle())
                        .onTapGesture { model.closePanel() }
                }
                Group {
                    if model.functionsOpen {
                        AwesunFunctionSheet(model: model, height: size.height * 0.79)
                    } else {
                        switch model.sheet {
                        case .mode: AwesunModeSheet(model: model)
                        case .lock: AwesunLockSheet(model: model)
                        case .guide: AwesunGuideSheet(model: model)
                        case .actions: AwesunActionPanel(model: model, height: panelHeight)
                        case .displaySettings: AwesunDisplayPanel(model: model, height: panelHeight)
                        case .keyboardMore:
                            AwesunKeyboardDeck(model: model, height: min(240, size.height * 0.42)) {
                                AwesunKeyboardAccessory(model: model, inDeck: true)
                            }
                        case .keyboardLayout:
                            AwesunAccessoryEditor(model: model, height: size.height * 0.88)
                        case .keyboardFull:
                            AwesunKeyboardView(model: model, maxHeight: size.height * 0.72)
                        case .gamepad: AwesunGamePanel(model: model)

                        case .displays: actionSheet(
                            "切换屏幕", (0..<model.displayCount).map {
                                "屏幕 \($0 + 1)" + ($0 == model.selectedDisplay ? "   ✓" : "")
                            }
                        ) { index in
                            model.selectDisplay(index)
                        }
                        case .shortcuts:
                            AwesunShortcutPanel(model: model, width: size.width, maxHeight: panelHeight)
                        case .none: EmptyView()
                        }
                    }
                }
                .background {
                    if model.isKeyboardPanel {
                        GeometryReader { geometry in
                            Color.clear.preference(key: AwesunKeyboardPanelSize.self,
                                                   value: geometry.size.height)
                        }
                    }
                }
                .padding(.bottom, model.keyboardInset)
            }
            .transition(.opacity)
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

struct AwesunKeyboardAccessory: View {
    static let height: CGFloat = 38
    @ObservedObject var model: AwesunSessionModel
    var inDeck = false

    var body: some View {
        HStack(spacing: 4) {
            accessoryButton("自定义", width: 50) { model.openKeyboardPanel(.keyboardLayout) }
            accessoryButton("快捷键", width: 50) { model.openKeyboardPanel(.shortcuts) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.accessoryKeys, id: \.self) { code in
                        if let shortcut = model.customShortcut(for: code) {
                            accessoryButton(shortcut.title, width: 80) {
                                model.sendShortcut(shortcut)
                            }
                        } else if let key = AwesunKeyboardLayout.keyByCode[code] {
                            accessoryButton(AwesunKeyboardLayout.title(for: key),
                                selected: model.modifiers.contains(key.label), width: 38) {
                                model.sendAccessoryKey(key)
                            }
                        }
                    }
                }
            }
            accessoryButton("全键盘", width: 43) { model.openKeyboardPanel(.keyboardFull) }
            accessoryButton("•••", selected: inDeck, width: 31) {
                if inDeck { model.showSystemKeyboardFromDeck() }
                else { model.openKeyboardPanel(.keyboardMore) }
            }
            accessoryButton("✕", width: 33, action: model.dismissRemoteKeyboard)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(AwesunPalette.keyboardDeck)
    }

    private func accessoryButton(_ title: String, selected: Bool = false,
                                 width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: width, height: 28)
                .background(selected ? AwesunPalette.brandBlue : Color.white.opacity(0.09))
                .cornerRadius(7)
                .frame(height: Self.height)
                .contentShape(Rectangle())
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
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

    static let controlRadius: CGFloat = 20
    static let controlEdge: CGFloat = 14
    static let glyphSize: CGFloat = 24

    static func rail(_ index: Int, in size: CGSize) -> CGPoint {
        let bottom = min(size.height - controlEdge - controlRadius, size.height * 0.933)
        let spacing: CGFloat = 48
        return CGPoint(x: size.width - controlEdge - controlRadius,
                       y: bottom - CGFloat(2 - index) * spacing)
    }

    static func dockCenter(_ placement: AwesunDockPlacement, in size: CGSize) -> CGPoint {
        let edge = controlEdge + controlRadius
        let bottom = placement.right ? rail(0, in: size).y - 48 : size.height - edge
        return CGPoint(x: placement.right ? size.width - edge : edge,
                       y: max(edge, min(bottom, placement.fraction * size.height)))
    }

    static func mouseArea(in size: CGSize, obstruction: CGFloat) -> CGSize {
        CGSize(width: size.width, height: max(1, size.height - obstruction))
    }

    static func mouseGeometry(_ center: CGPoint?, in size: CGSize, viewport: CGRect?,
                              obstruction: CGFloat) -> AwesunMouseGeometry {
        let area = mouseArea(in: size, obstruction: obstruction)
        let screen = CGRect(origin: .zero, size: area)
        let video = viewport?.intersection(screen) ?? screen
        let visible = video.isNull || video.isEmpty ? screen : video
        let controlsScale = obstruction > 0 ? min(1, max(0.25, area.height / mouseSize)) : 1
        let gap = CGSize(width: 94 * controlsScale, height: 72 * controlsScale)
        let rightButton = (arcRadius + arcWidth / 2) * controlsScale
        let lowerButton = (wheelOffset + wheelRadius) * controlsScale
        let minCenter = CGPoint(x: visible.minX + gap.width, y: visible.minY + gap.height)
        let maxCenter = CGPoint(
            x: max(minCenter.x, min(screen.maxX - rightButton, visible.maxX - 1 + gap.width)),
            y: max(minCenter.y, min(screen.maxY - lowerButton, visible.maxY - 1 + gap.height)))
        let raw = center ?? CGPoint(x: size.width * 0.64, y: size.height * 0.56)
        let center = CGPoint(x: min(max(raw.x, minCenter.x), maxCenter.x),
                             y: min(max(raw.y, minCenter.y), maxCenter.y))
        let tip = CGPoint(x: center.x - gap.width, y: center.y - gap.height)
        return AwesunMouseGeometry(center: center, pointer: tip,
                                  minCenter: minCenter, maxCenter: maxCenter, scale: controlsScale)
    }

    static func circle(_ point: CGPoint, at center: CGPoint, radius: CGFloat) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= radius
    }

    static func mouseRegion(_ point: CGPoint, model: AwesunSessionModel,
                            size: CGSize) -> AwesunMouseRegion? {
        guard model.mouseVisible && !model.mouseCollapsed else { return nil }
        let layout = mouseGeometry(model.mouseAnchor, in: size, viewport: model.mouseViewport,
                                   obstruction: model.mouseObstruction)
        let local = CGPoint(x: (point.x - layout.center.x) / layout.scale,
                            y: (point.y - layout.center.y) / layout.scale)
        if circle(local, at: CGPoint(x: closeOffset.width, y: closeOffset.height), radius: 16) {
            return .close
        }
        if model.wheelOpen {
            return abs(hypot(local.x, local.y) - ringRadius) <= ringThickness / 2 ? .ring : nil
        }
        if circle(local, at: .zero, radius: hub) { return .hub }
        if circle(local, at: CGPoint(x: 0, y: -wheelOffset), radius: 20) { return .wheelTop }
        if circle(local, at: CGPoint(x: 0, y: wheelOffset), radius: 20) { return .wheelBottom }

        let half = mouseSize / 2
        let rect = CGRect(origin: .zero, size: CGSize(width: mouseSize, height: mouseSize))
        let p = CGPoint(x: local.x + half, y: local.y + half)
        for side in [AwesunMouseRegion.left, .right] {
            if band(side).path(in: rect).contains(p) { return side }
        }
        return nil
    }

    static func band(_ side: AwesunMouseRegion) -> AwesunArcBand {
        AwesunArcBand(centerDeg: side == .left ? 180 : 0, spanDeg: arcSpan,
                      radius: arcRadius, thickness: arcWidth)
    }
}

private struct AwesunKeyboardPanelSize: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AwesunMouseGeometry {
    let center: CGPoint
    let pointer: CGPoint
    let minCenter: CGPoint
    let maxCenter: CGPoint
    let scale: CGFloat

    static func hubVelocity(from hub: CGRect, toward touch: CGPoint) -> CGSize {
        let dx = touch.x - hub.midX
        let dy = touch.y - hub.midY
        let distance = hypot(dx, dy)
        let radius = hub.width / 2
        guard distance > radius else { return .zero }
        let speed = min(600, (distance - radius) * 8)
        return CGSize(width: -dx / distance * speed, height: -dy / distance * speed)
    }

    func canvasVelocity(toward requestedCenter: CGPoint) -> CGSize {
        let speed: CGFloat = 600
        func axis(_ requested: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            if requested < lower { return speed }
            if requested > upper { return -speed }
            return 0
        }
        return CGSize(width: axis(requestedCenter.x, minCenter.x, maxCenter.x),
                      height: axis(requestedCenter.y, minCenter.y, maxCenter.y))
    }
}

enum AwesunMouseRegion: Equatable {
    case hub, left, right, wheelTop, wheelBottom, ring, close
}

struct AwesunVirtualMouseView: View {
    @ObservedObject var model: AwesunSessionModel
    let screenSize: CGSize

    var body: some View {
        let area = AwesunControlLayout.mouseArea(in: screenSize, obstruction: model.mouseObstruction)
        let geometry = AwesunControlLayout.mouseGeometry(
            model.mouseAnchor, in: screenSize, viewport: model.mouseViewport,
            obstruction: model.mouseObstruction)
        let pointer = geometry.pointer
        let center = geometry.center
        if model.mouseCollapsed {
            AwesunDockButton(placement: $model.mousePlacement, size: area,
                             label: "展开虚拟鼠标",
                             tap: model.expandMouse) {
                Image(AwesunIcons.mouse).renderingMode(.template).resizable().scaledToFit()
            }
        } else {
            ZStack {
                if model.wheelOpen {
                    scrollRing(at: pointer)
                } else {
                    arc(.left).accessibilityLabel("鼠标左键")
                        .accessibilityAction { model.click("left", at: pointer) }
                    arc(.right).accessibilityLabel("鼠标右键")
                        .accessibilityAction { model.click("right", at: pointer) }
                    let hubActive = model.pressedMouseRegion == .hub || model.dragging
                    Circle()
                        .fill(LinearGradient(
                            colors: hubActive
                                ? [AwesunPalette.activeIce, AwesunPalette.activeBlue]
                                : [Color.white.opacity(0.26), AwesunPalette.mouseFill],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(
                            Circle().strokeBorder(
                                hubActive ? AwesunPalette.mouseActiveStroke : Color.white.opacity(0.34),
                                lineWidth: 1.5
                            )
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                .padding(6)
                        )
                        .overlay {
                            ZStack {
                                ForEach(0..<4, id: \.self) { idx in
                                    Capsule()
                                        .fill(Color.white.opacity(hubActive ? 0.85 : 0.45))
                                        .frame(width: 1.5, height: 4)
                                        .offset(y: -10)
                                        .rotationEffect(.degrees(Double(idx) * 90))
                                }
                                Circle()
                                    .fill(hubActive ? Color.white : AwesunPalette.activeIce)
                                    .frame(width: 6.5, height: 6.5)
                            }
                        }
                        .frame(width: AwesunControlLayout.hub * 2, height: AwesunControlLayout.hub * 2)
                        .accessibilityLabel("移动光标")
                    smallButton(.wheelTop).offset(y: -AwesunControlLayout.wheelOffset)
                        .accessibilityLabel("滑动滚轮")
                        .accessibilityAction { model.scroll(1, at: pointer) }
                        .accessibilityAction(named: Text("打开圆形滚轮")) { model.openWheel() }
                    smallButton(.wheelBottom).offset(y: AwesunControlLayout.wheelOffset)
                        .accessibilityLabel("鼠标中键")
                        .accessibilityAction { model.click("middle", at: pointer) }
                }
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(AwesunPalette.mouseFill)
                            .overlay(Circle().strokeBorder(AwesunPalette.mouseStroke, lineWidth: 1.2))
                    )
                    .accessibilityLabel(model.wheelOpen ? "退出圆形滚轮" : "收起虚拟鼠标")
                    .accessibilityAction { model.closeWheelOrMouse() }
                    .offset(AwesunControlLayout.closeOffset)
            }
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 6)
            .frame(width: AwesunControlLayout.mouseSize, height: AwesunControlLayout.mouseSize)
            .scaleEffect(geometry.scale)
            .position(center)
            .allowsHitTesting(false)

            AwesunPointerGlyph()
                .fill(.white)
                .overlay(AwesunPointerGlyph().stroke(.black.opacity(0.9), lineWidth: 1.4))
                .shadow(color: .black.opacity(0.55), radius: 1, x: 0, y: 1)
                .frame(width: 15, height: 21)
                .position(x: pointer.x + 7.5, y: pointer.y + 10.5)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func scrollRing(at pointer: CGPoint) -> some View {
        AwesunAnnulus()
            .fill(AwesunPalette.mouseFill, style: FillStyle(eoFill: true))
            .overlay(AwesunAnnulus().stroke(AwesunPalette.mouseStroke, lineWidth: 1.2))
            .overlay {
                ZStack {
                    ForEach(0..<24, id: \.self) { idx in
                        Capsule()
                            .fill(idx % 6 == 0 ? AwesunPalette.activeIce.opacity(0.75) : Color.white.opacity(0.24))
                            .frame(width: idx % 6 == 0 ? 1.6 : 1.0, height: idx % 6 == 0 ? 10 : 6)
                            .offset(y: -AwesunControlLayout.ringRadius)
                            .rotationEffect(.degrees(Double(idx) * 15))
                    }
                    if let angle = model.wheelIndicator {
                        ZStack {
                            Circle()
                                .fill(AwesunPalette.activeIce)
                                .frame(width: 21, height: 21)
                                .blur(radius: 3)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 9, height: 9)
                        }
                        .offset(x: AwesunControlLayout.ringRadius * cos(angle),
                                y: AwesunControlLayout.ringRadius * sin(angle))
                    }
                }
            }
            .accessibilityLabel("圆形滚轮")
            .accessibilityAdjustableAction { direction in
                if direction == .increment { model.scroll(-1, at: pointer) }
                if direction == .decrement { model.scroll(1, at: pointer) }
            }
    }

    private func arc(_ side: AwesunMouseRegion) -> some View {
        let band = AwesunControlLayout.band(side)
        let active = model.pressedMouseRegion == side || (side == .left && model.dragging)
        return ZStack {
            band.fill(active ? AwesunPalette.activeBlue : AwesunPalette.mouseFill)
                .overlay(band.stroke(active ? AwesunPalette.mouseActiveStroke : AwesunPalette.mouseStroke, lineWidth: 1.4))
            Text(side == .left ? "L" : "R")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(active ? .white : AwesunPalette.textSecondary)
                .offset(x: side == .left ? -AwesunControlLayout.arcRadius : AwesunControlLayout.arcRadius)
        }
    }

    private func smallButton(_ region: AwesunMouseRegion) -> some View {
        let active = model.pressedMouseRegion == region
        return Circle()
            .fill(active ? AwesunPalette.activeBlue : AwesunPalette.mouseFill)
            .overlay(Circle().strokeBorder(active ? AwesunPalette.mouseActiveStroke : AwesunPalette.mouseStroke, lineWidth: 1.4))
            .overlay {
                if region == .wheelBottom {
                    VStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Capsule().fill(Color.white.opacity(0.68)).frame(width: 12, height: 1.4)
                        }
                    }
                } else if region == .wheelTop {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                }
            }
            .frame(width: 28, height: 28)
    }
}

struct AwesunPointerGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.62))
            path.addLine(to: CGPoint(x: rect.width * 0.60, y: rect.height * 0.66))
            path.addLine(to: CGPoint(x: rect.width * 0.79, y: rect.height * 0.92))
            path.addLine(to: CGPoint(x: rect.width * 0.57, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width * 0.39, y: rect.height * 0.73))
            path.addLine(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.89))
            path.closeSubpath()
        }
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

struct AwesunDockPlacement: Codable {
    var right = true
    var fraction: CGFloat
}

struct AwesunFloatingChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var accent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let control = content
            .frame(width: AwesunControlLayout.glyphSize, height: AwesunControlLayout.glyphSize)
            .frame(width: AwesunControlLayout.controlRadius * 2,
                   height: AwesunControlLayout.controlRadius * 2)
            .contentShape(Circle())
        fallback(control)
    }

    private func fallback(_ control: some View) -> some View {
        control
            .foregroundColor(accent ? AwesunPalette.activeIce : .white)
            .background {
                if reduceTransparency {
                    Circle().fill(AwesunPalette.sheetSolid)
                } else {
                    Circle().fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(Circle().fill(LinearGradient(
                            colors: [Color(awesun: 0xCD26344A), Color(awesun: 0xE6182030)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
            }
            .overlay(Circle().strokeBorder(
                accent ? AwesunPalette.activeIce.opacity(0.45) : AwesunPalette.mouseStroke,
                lineWidth: 1).allowsHitTesting(false))
            .shadow(color: accent ? AwesunPalette.brandBlue.opacity(0.32) : .black.opacity(0.36),
                    radius: 11, x: 0, y: 8)
    }
}

struct AwesunDockButton<Glyph: View>: View {
    @Binding var placement: AwesunDockPlacement
    let size: CGSize
    let label: String
    let tap: () -> Void
    @ViewBuilder let glyph: () -> Glyph
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        let anchor = AwesunControlLayout.dockCenter(placement, in: size)
        let button = CGPoint(x: anchor.x + drag.width, y: anchor.y + drag.height)
        glyph()
            .modifier(AwesunFloatingChrome())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("awesunControls"))
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    if hypot(value.translation.width, value.translation.height) < 7 {
                        tap()
                    } else {
                        let x = anchor.x + value.translation.width
                        let y = anchor.y + value.translation.height
                        withAnimation(.easeOut(duration: 0.18)) {
                            placement = AwesunDockPlacement(
                                right: x >= size.width / 2,
                                fraction: min(1, max(0, y / max(1, size.height))))
                        }
                    }
                })
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap() }
            .accessibilityAction(named: Text("移到左侧")) { placement.right = false }
            .accessibilityAction(named: Text("移到右侧")) { placement.right = true }
            .position(button)
    }
}
