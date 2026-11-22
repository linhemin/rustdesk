import Flutter
import Photos
import SwiftUI
import UIKit

final class AwesunSessionOverlay {
    static let shared = AwesunSessionOverlay()

    private var model = AwesunSessionModel()
    private var host: UIHostingController<AwesunSessionRootView>?
    private var surface: AwesunTouchSurface?
    private weak var installedIn: UIViewController?

    private init() {}

    func installIfNeeded(window: UIWindow?) {
        guard installedIn == nil, let root = window?.rootViewController,
              let flutterVC = findFlutterController(root) else { return }
        installedIn = flutterVC

        let channel = FlutterMethodChannel(name: "awesun/session", binaryMessenger: flutterVC.binaryMessenger)
        AwesunBridge.shared.attach(channel: channel)
        AwesunVideoTexture.shared.attach(
            registry: flutterVC.registrar(forPlugin: "RustDeskVideoTexture")?.textures(),
            channel: channel
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "setActive":
                result(self.setActive(args["active"] as? Bool == true, touchMode: args["touchMode"] as? Bool == true))
            case "setPresentation":
                self.setPresentation(args)
                result(nil)
            case "savePhoto":
                self.savePhoto((call.arguments as? FlutterStandardTypedData)?.data, result: result)
            case "setVideoTexture":
                result(AwesunVideoTexture.shared.configure(enabled: args["enabled"] as? Bool == true))
            case "saveTexturePhoto":
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = AwesunVideoTexture.shared.screenshotPNG()
                    DispatchQueue.main.async { self.savePhoto(data, result: result) }
                }
            case "setMouseViewport":
                if let x = args["x"] as? Double, let y = args["y"] as? Double,
                   let width = args["width"] as? Double, let height = args["height"] as? Double {
                    self.model.mouseViewport = CGRect(x: x, y: y, width: width, height: height)
                }
                result(nil)
            case "setPerformanceStatus":
                self.model.updatePerformance(args)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let surface = AwesunTouchSurface(model: model)
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.isHidden = true
        let host = UIHostingController(rootView: AwesunSessionRootView(model: model))
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.translatesAutoresizingMaskIntoConstraints = false

        flutterVC.addChild(host)
        flutterVC.view.addSubview(surface)
        surface.addSubview(host.view)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: flutterVC.view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: flutterVC.view.trailingAnchor),
            surface.topAnchor.constraint(equalTo: flutterVC.view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: flutterVC.view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: surface.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
        host.didMove(toParent: flutterVC)
        self.surface = surface
        self.host = host
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelMouseInput),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard model.active, let surface = surface, let window = surface.window,
              let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return }
        let inWindow = window.convert(value.cgRectValue, from: window.screen.coordinateSpace)
        let end = surface.convert(inWindow, from: window)
        let overlap = surface.bounds.intersection(end)
        let docked = !overlap.isEmpty && end.maxY >= surface.bounds.maxY - 1
        AwesunBridge.shared.command("systemKeyboardTarget", ["inset": docked ? Double(overlap.height) : 0])
    }

    @objc private func cancelMouseInput() {
        surface?.mouseInput.cancel()
    }

    private func setActive(_ active: Bool, touchMode: Bool) -> Bool {
        guard let host = host, let surface = surface else { return false }
        if !active && model.active {
            _ = AwesunVideoTexture.shared.configure(enabled: false)
            surface.mouseInput.cancel()
            model.endDrag()
            model.pauseMouseIdleTimer()
            model.releaseModifiers()
            model.active = false
            model = AwesunSessionModel()
            surface.model = model
            host.rootView = AwesunSessionRootView(model: model)
        }
        model.mode = touchMode ? .touch : .pointer
        model.active = active
        surface.isHidden = !active
        return true
    }

    private func setPresentation(_ values: [String: Any]) {
        let obscured = values["obscured"] as? Bool == true
        let inset = CGFloat(values["keyboardInset"] as? Double ?? 0)
        if obscured {
            surface?.mouseInput.cancel()
            model.endDrag()
            model.pauseMouseIdleTimer()
            model.closeObscuredPanels()
            model.releaseModifiers()
        }
        if model.keyboardInset != 0 && inset == 0 {
            model.releaseModifiers()
        }
        if model.keyboardInset != inset {
            let before = model.mouseObstruction
            model.keyboardInset = inset
            if model.mouseObstruction > before, let size = surface?.bounds.size {
                model.keepVirtualMouseReachable(in: size)
            }
        }
        surface?.isHidden = !model.active || obscured
        if !obscured { model.refreshMouseIdleTimer() }
    }

    private func savePhoto(_ png: Data?, result: @escaping FlutterResult) {
        guard let data = png, !data.isEmpty else { result("encodeFailed"); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { result("permissionDenied") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            } completionHandler: { saved, _ in
                DispatchQueue.main.async { result(saved ? "saved" : "saveFailed") }
            }
        }
    }

    private func findFlutterController(_ controller: UIViewController) -> FlutterViewController? {
        if let flutter = controller as? FlutterViewController { return flutter }
        for child in controller.children {
            if let flutter = findFlutterController(child) { return flutter }
        }
        if let presented = controller.presentedViewController { return findFlutterController(presented) }
        return nil
    }
}

private final class AwesunTouchSurface: UIView {
    var model: AwesunSessionModel

    lazy var mouseInput = AwesunMouseInput(surface: self)

    init(model: AwesunSessionModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
        mouseInput.frame = bounds
        mouseInput.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(mouseInput)
    }

    required init?(coder: NSCoder) { nil }

    fileprivate var mouseAvailable: Bool {
        model.active && !model.functionsOpen && (model.sheet == nil || model.isKeyboardPanel)
    }

    private var mouseArea: CGSize {
        AwesunControlLayout.mouseArea(in: bounds.size, obstruction: model.mouseObstruction)
    }

    private func floatingControl(at point: CGPoint) -> Bool {
        guard model.mouseObstruction == 0 else { return false }
        let size = bounds.size
        let controls = [AwesunControlLayout.dockCenter(model.lockPlacement, in: size)] +
            (0..<3).map { AwesunControlLayout.rail($0, in: size) }
        return controls.contains {
            AwesunControlLayout.circle(point, at: $0, radius: AwesunControlLayout.controlRadius)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !isHidden && isUserInteractionEnabled && bounds.contains(point) &&
            mouseAvailable && point.y < mouseArea.height && !floatingControl(at: point) {
            if mouseInput.ownsCanvasTouches { return mouseInput }
            if AwesunControlLayout.mouseRegion(point, model: model, size: bounds.size) != nil {
                return mouseInput.canStart ? mouseInput : nil
            }
        }
        return super.hitTest(point, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        if model.functionsOpen || (model.sheet != nil && !model.isKeyboardPanel) { return true }

        let area = mouseArea
        if model.mouseObstruction > 0 && point.y >= area.height {
            return point.y < bounds.height - model.keyboardInset
        }
        if model.mouseVisible && model.mouseCollapsed &&
            AwesunControlLayout.circle(point, at: AwesunControlLayout.dockCenter(model.mousePlacement, in: area),
                                       radius: AwesunControlLayout.controlRadius) {
            return true
        }
        return floatingControl(at: point)
    }
}

private final class AwesunMouseInput: UIView {
    private weak var surface: AwesunTouchSurface?
    private var contact: UITouch?
    private var canvasContact: UITouch?
    private var canvasPrevious: CGPoint = .zero
    private var region: AwesunMouseRegion?
    private var start: CGPoint = .zero
    private var startingHub: CGRect = .zero
    private var moved = false
    private let dragThreshold: CGFloat = 5
    private var hubTap: Task<Void, Never>?
    private var wheelAngle: Double?
    private var wheelRemainder = 0.0
    private var panTimer: Timer?
    private let panInterval: TimeInterval = 1.0 / 30.0
    private enum PanTravel {
        case outward(peak: CGFloat)
        case braked(low: CGFloat)
    }
    private var panTravel = PanTravel.outward(peak: 0)

    init(surface: AwesunTouchSurface) {
        self.surface = surface
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { nil }

    // The surface assigns touches; this full-screen view does not claim them on its own.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    var canStart: Bool { contact == nil }
    var ownsCanvasTouches: Bool {
        (region == .hub || region == .left) && surface?.model.displayLocked == false
    }

    private func geometry(_ surface: AwesunTouchSurface, center: CGPoint? = nil) -> AwesunMouseGeometry {
        AwesunControlLayout.mouseGeometry(center ?? surface.model.mouseAnchor, in: bounds.size,
                                          viewport: surface.model.mouseViewport,
                                          obstruction: surface.model.mouseObstruction)
    }

    private func pointer(_ surface: AwesunTouchSurface) -> CGPoint {
        geometry(surface).pointer
    }

    private func requestedCenter(for point: CGPoint) -> CGPoint {
        CGPoint(x: startingHub.midX + point.x - start.x, y: startingHub.midY + point.y - start.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let surface = surface else { return }
        if contact == nil {
            for touch in touches {
                let point = touch.location(in: self)
                if let hit = AwesunControlLayout.mouseRegion(point, model: surface.model, size: bounds.size) {
                    beginMouseContact(touch, at: point, hit: hit, surface: surface)
                    break
                }
            }
        }
        if ownsCanvasTouches, canvasContact == nil, let other = touches.first(where: {
            $0 !== contact && AwesunControlLayout.mouseRegion(
                $0.location(in: self), model: surface.model, size: bounds.size) == nil
        }) {
            canvasContact = other
            canvasPrevious = other.location(in: self)
            moved = true
            hubTap?.cancel()
            hubTap = nil
            stopPanning(interruptCanvas: true)
        }
    }

    private func beginMouseContact(_ touch: UITouch, at point: CGPoint, hit: AwesunMouseRegion,
                                   surface: AwesunTouchSurface) {
        contact = touch
        region = hit
        start = point
        let layout = geometry(surface)
        let radius = AwesunControlLayout.hub * layout.scale
        startingHub = CGRect(x: layout.center.x - radius, y: layout.center.y - radius,
                             width: 2 * radius, height: 2 * radius)
        panTravel = .outward(peak: 0)
        moved = false
        AwesunBridge.shared.command("interruptCanvasPan")
        let model = surface.model
        if hit != .hub {
            hubTap?.cancel()
            hubTap = nil
        }
        model.pressedMouseRegion = hit
        model.mouseGesture(true)
        switch hit {
        case .left:
            model.haptic()
            model.beginDrag(at: pointer(surface))
        case .ring:
            updateWheel(at: point)
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let surface = surface, surface.mouseAvailable else { cancel(); return }
        if let other = canvasContact {
            if touches.contains(other) {
                let point = other.location(in: self)
                let delta = CGSize(width: point.x - canvasPrevious.x, height: point.y - canvasPrevious.y)
                canvasPrevious = point
                if !surface.model.displayLocked && delta != .zero {
                    let tip = pointer(surface)
                    AwesunBridge.shared.command("panCanvasBy", [
                        "x": Double(tip.x), "y": Double(tip.y),
                        "dx": Double(delta.width), "dy": Double(delta.height)
                    ])
                }
            }
            return
        }
        guard let touch = contact, touches.contains(touch), let region = region else { return }
        let current = touch.location(in: self)
        let distance = hypot(current.x - start.x, current.y - start.y)
        moved = moved || distance >= dragThreshold
        switch region {
        case .left, .hub:
            if moved {
                hubTap?.cancel()
                hubTap = nil
                let next = requestedCenter(for: current)
                let layout = geometry(surface, center: next)
                surface.model.moveVirtualPointer(anchor: layout.center, point: layout.pointer)
                updatePanning(at: current, layout: layout, locked: surface.model.displayLocked)
            }
        case .wheelTop:
            if moved {
                if !surface.model.wheelOpen {
                    surface.model.openWheel()
                    updateWheel(at: start)
                }
                updateWheel(at: current)
            }
        case .ring:
            updateWheel(at: current)
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let other = canvasContact, touches.contains(other), let touch = contact, !touches.contains(touch) {
            endCanvasContact()
            return
        }
        guard let touch = contact, touches.contains(touch),
              let region = region, let surface = surface else { return }
        let model = surface.model
        guard surface.mouseAvailable else { cancel(); return }
        let end = touch.location(in: self)
        let tapLimit: CGFloat = region == .wheelTop ? dragThreshold : 8
        let tapped = !moved && hypot(end.x - start.x, end.y - start.y) < tapLimit
        let target = pointer(surface)
        finish()
        guard tapped else { return }
        switch region {
        case .hub:
            if let pending = hubTap {
                pending.cancel()
                hubTap = nil
                model.collapseMouse()
            } else {
                hubTap = Task { @MainActor [weak self, weak model] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    self?.hubTap = nil
                    if let model = model, model.mouseVisible && !model.mouseCollapsed &&
                        !model.functionsOpen && (model.sheet == nil || model.isKeyboardPanel) {
                        model.click("left", at: target)
                    }
                }
            }
        case .right:
            model.click("right", at: target)
        case .wheelTop:
            if !model.wheelOpen { model.scroll(1, at: target) }
        case .wheelBottom:
            model.haptic()
            model.openWheel()
        case .close:
            model.closeWheelOrMouse()
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = contact, touches.contains(touch) { cancel() }
        else if let other = canvasContact, touches.contains(other) { endCanvasContact() }
    }

    private func endCanvasContact() {
        canvasContact = nil
        stopPanning(interruptCanvas: true)
        guard let touch = contact, let surface = surface else { return }
        // Resume from the still-held finger without replaying motion made during the handoff.
        start = touch.location(in: self)
        let layout = geometry(surface)
        startingHub.origin = CGPoint(x: layout.center.x - startingHub.width / 2,
                                     y: layout.center.y - startingHub.height / 2)
        panTravel = .braked(low: panExcursion(at: start, layout: layout))
    }

    func cancel() {
        hubTap?.cancel()
        hubTap = nil
        if contact != nil { finish() }
    }

    private func finish() {
        stopPanning(interruptCanvas: true)
        let temporaryWheel = region == .wheelTop
        canvasContact = nil
        contact = nil
        region = nil
        wheelAngle = nil
        wheelRemainder = 0
        if let model = surface?.model {
            model.endDrag()
            model.pressedMouseRegion = nil
            model.wheelIndicator = nil
            if temporaryWheel && model.wheelOpen { model.closeWheelOrMouse() }
            model.mouseGesture(false)
        }
    }

    private func panVelocity(at point: CGPoint, layout: AwesunMouseGeometry) -> CGSize {
        if region == .hub {
            return AwesunMouseGeometry.hubVelocity(from: startingHub, toward: point)
        }
        return layout.canvasVelocity(toward: requestedCenter(for: point))
    }

    private func panExcursion(at point: CGPoint, layout: AwesunMouseGeometry) -> CGFloat {
        if region == .hub {
            return max(0, hypot(point.x - startingHub.midX, point.y - startingHub.midY) - startingHub.width / 2)
        }
        let target = requestedCenter(for: point)
        return hypot(target.x - layout.center.x, target.y - layout.center.y)
    }

    private func updatePanning(at point: CGPoint, layout: AwesunMouseGeometry, locked: Bool) {
        let velocity = panVelocity(at: point, layout: layout)
        guard !locked && velocity != .zero else {
            panTravel = .outward(peak: 0)
            stopPanning()
            return
        }
        // Compare against the turning point so several sub-point movements count as a pullback.
        let excursion = panExcursion(at: point, layout: layout)
        let reversal: CGFloat = 3
        switch panTravel {
        case let .outward(peak):
            if peak - excursion >= reversal {
                panTravel = .braked(low: excursion)
                stopPanning()
                return
            }
            panTravel = .outward(peak: max(peak, excursion))
        case let .braked(low):
            let low = min(low, excursion)
            guard excursion - low >= reversal else {
                panTravel = .braked(low: low)
                return
            }
            panTravel = .outward(peak: excursion)
        }
        guard panTimer == nil else { return }
        let timer = Timer(timeInterval: panInterval, repeats: true) { [weak self] timer in
            if self == nil {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self, self.panTimer === timer else { return }
                self.advancePanning()
            }
        }
        panTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        advancePanning()
    }

    private func advancePanning() {
        guard let surface = surface, surface.mouseAvailable, !surface.isHidden else { cancel(); return }
        guard let contact = contact, !surface.model.displayLocked else {
            stopPanning()
            return
        }
        let layout = geometry(surface)
        let velocity = panVelocity(at: contact.location(in: self), layout: layout)
        guard velocity != .zero else {
            stopPanning()
            return
        }
        AwesunBridge.shared.virtualMove(to: layout.pointer, canvasDelta: CGSize(
            width: velocity.width * panInterval, height: velocity.height * panInterval))
    }

    private func stopPanning(interruptCanvas: Bool = false) {
        if interruptCanvas || panTimer != nil { AwesunBridge.shared.command("interruptCanvasPan") }
        panTimer?.invalidate()
        panTimer = nil
    }

    private func updateWheel(at point: CGPoint) {
        guard let surface = surface else { return }
        let layout = geometry(surface)
        let dx = point.x - layout.center.x
        let dy = point.y - layout.center.y
        guard hypot(dx, dy) >= AwesunControlLayout.ringRadius * layout.scale / 2 else {
            wheelAngle = nil
            return
        }
        let angle = Double(atan2(dy, dx))
        if let previous = wheelAngle {
            let delta = angle - previous
            wheelRemainder += atan2(sin(delta), cos(delta))
            let step = Double.pi / 12
            let ticks = Int(wheelRemainder / step)
            if ticks != 0 {
                surface.model.scroll(-ticks, at: pointer(surface))
                wheelRemainder -= Double(ticks) * step
            }
        }
        wheelAngle = angle
        surface.model.wheelIndicator = angle
    }
}

struct AwesunSessionRootView: View {
    @ObservedObject var model: AwesunSessionModel

    var body: some View {
        GeometryReader { geometry in
            if model.active {
                AwesunSessionView(model: model, size: geometry.size)
            }
        }
        .ignoresSafeArea()
    }
}
