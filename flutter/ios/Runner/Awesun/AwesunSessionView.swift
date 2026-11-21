import SwiftUI

struct AwesunSessionView: View {
    @ObservedObject var model: AwesunSessionModel
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.keyboardInset > 0 {
                keyboardAccessory(inDeck: false).position(
                    x: size.width / 2, y: size.height - model.keyboardInset - 19
                )
            } else {
                if model.mouseVisible {
                    AwesunVirtualMouseView(model: model, screenSize: size)
                }
                controls
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
                .foregroundColor(accent ? AwesunPalette.brandRed : .white)
                .modifier(AwesunFloatingChrome())
        }
        .buttonStyle(AwesunPressStyle())
        .accessibilityLabel(Text(label))
    }

    private func keyboardAccessory(inDeck: Bool) -> some View {
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
        .padding(4)
        .frame(width: size.width, height: 38)
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
                .background(selected ? AwesunPalette.brandRed : Color.white.opacity(0.09))
                .cornerRadius(7)
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sheetLayer: some View {
        if model.functionsOpen || (model.sheet != nil &&
            !(model.isKeyboardPanel && model.keyboardInset > 0)) {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35).onTapGesture { model.closePanel() }
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
                                keyboardAccessory(inDeck: true)
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

    static func mouseAnchor(_ position: CGPoint?, in size: CGSize) -> CGPoint {
        let start = position ?? CGPoint(x: size.width * 0.64 - 94, y: size.height * 0.56 - 72)
        return CGPoint(x: min(max(0, start.x), max(0, size.width - 1)),
                       y: min(max(0, start.y), max(0, size.height - 1)))
    }

    static func pointer(_ position: CGPoint?, in size: CGSize, viewport: CGRect?) -> CGPoint {
        let anchor = mouseAnchor(position, in: size)
        let screen = CGRect(origin: .zero, size: size)
        let visible = viewport.map { $0.intersection(screen) } ?? screen
        let bounds = visible.isNull || visible.isEmpty ? screen : visible
        return CGPoint(x: min(max(anchor.x, bounds.minX), max(bounds.minX, bounds.maxX - 1)),
                       y: min(max(anchor.y, bounds.minY), max(bounds.minY, bounds.maxY - 1)))
    }

    static func mouseCenter(_ position: CGPoint?, in size: CGSize, viewport: CGRect?) -> CGPoint {
        let anchor = mouseAnchor(position, in: size)
        let tip = pointer(anchor, in: size, viewport: viewport)
        let horizontalGap: CGFloat = 94
        let switchSide = max(size.width / 2, size.width - arcRadius - 12 - horizontalGap)
        // Keep the upper wheel trigger and the hub reachable as the lower controls extend off-screen.
        let upperLimit = min(wheelOffset + 20, size.height / 2)
        let lowerLimit = max(upperLimit, size.height - 14)
        return CGPoint(x: tip.x + (tip.x <= switchSide ? horizontalGap : -horizontalGap),
                       y: min(max(anchor.y + 72, upperLimit), lowerLimit))
    }

    static func circle(_ point: CGPoint, at center: CGPoint, radius: CGFloat) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= radius
    }

    static func mouseRegion(_ point: CGPoint, model: AwesunSessionModel,
                            size: CGSize) -> AwesunMouseRegion? {
        guard model.mouseVisible && !model.mouseCollapsed else { return nil }
        let center = mouseCenter(model.mouseAnchor, in: size, viewport: model.mouseViewport)
        let local = CGPoint(x: point.x - center.x, y: point.y - center.y)
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

enum AwesunMouseRegion: Equatable {
    case hub, left, right, wheelTop, wheelBottom, ring, close
}

struct AwesunVirtualMouseView: View {
    @ObservedObject var model: AwesunSessionModel
    let screenSize: CGSize

    var body: some View {
        let pointer = AwesunControlLayout.pointer(
            model.mouseAnchor, in: screenSize, viewport: model.mouseViewport)
        let center = AwesunControlLayout.mouseCenter(
            model.mouseAnchor, in: screenSize, viewport: model.mouseViewport)
        if model.mouseCollapsed {
            AwesunDockButton(placement: $model.mousePlacement, size: screenSize,
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
                    Circle()
                        .fill(model.pressedMouseRegion == .hub || model.dragging
                              ? AwesunPalette.brandRed : AwesunPalette.mouseFill)
                        .overlay(Circle().strokeBorder(.black.opacity(0.68), lineWidth: 2))
                        .frame(width: AwesunControlLayout.hub * 2, height: AwesunControlLayout.hub * 2)
                        .accessibilityLabel("移动光标")
                    smallButton(.wheelTop).offset(y: -AwesunControlLayout.wheelOffset)
                        .accessibilityLabel("滑动滚轮")
                        .accessibilityAction { model.scroll(1, at: pointer) }
                    smallButton(.wheelBottom).offset(y: AwesunControlLayout.wheelOffset)
                        .accessibilityLabel("打开圆形滚轮")
                        .accessibilityAction { model.openWheel() }
                }
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .background(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .accessibilityLabel(model.wheelOpen ? "退出圆形滚轮" : "收起虚拟鼠标")
                    .accessibilityAction { model.closeWheelOrMouse() }
                    .offset(AwesunControlLayout.closeOffset)
            }
            .frame(width: AwesunControlLayout.mouseSize, height: AwesunControlLayout.mouseSize)
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
            .fill(.white.opacity(0.27), style: FillStyle(eoFill: true))
            .overlay(AwesunAnnulus().stroke(.black.opacity(0.68), lineWidth: 2))
            .overlay {
                if let angle = model.wheelIndicator {
                    Circle().fill(Color(awesun: 0xFFF4BA58))
                        .frame(width: 23, height: 23)
                        .blur(radius: 2)
                        .offset(x: AwesunControlLayout.ringRadius * cos(angle),
                                y: AwesunControlLayout.ringRadius * sin(angle))
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
        return band.fill(model.pressedMouseRegion == side
                         ? AwesunPalette.brandRed : AwesunPalette.mouseFill)
            .overlay(band.stroke(.black.opacity(0.72), lineWidth: 2))
    }

    private func smallButton(_ region: AwesunMouseRegion) -> some View {
        Circle()
            .fill(model.pressedMouseRegion == region ? AwesunPalette.brandRed : AwesunPalette.mouseFill)
            .overlay(Circle().strokeBorder(.black.opacity(0.68), lineWidth: 2))
            .overlay {
                if region == .wheelBottom {
                    VStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Capsule().fill(.black.opacity(0.30)).frame(width: 13, height: 1.5)
                        }
                    }
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
    func body(content: Content) -> some View {
        content.frame(width: AwesunControlLayout.glyphSize, height: AwesunControlLayout.glyphSize)
            .frame(width: AwesunControlLayout.controlRadius * 2,
                   height: AwesunControlLayout.controlRadius * 2)
            .background(Circle().fill(Color.black.opacity(0.78)))
            .contentShape(Circle())
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
            .foregroundColor(.white)
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
