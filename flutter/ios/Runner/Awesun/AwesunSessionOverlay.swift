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
        NotificationCenter.default.addObserver(self, selector: #selector(cancelMouseInput),
                                               name: UIApplication.willResignActiveNotification, object: nil)
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
        if obscured || inset > 0 { surface?.mouseInput.cancel() }
        if obscured {
            model.endDrag()
            model.pauseMouseIdleTimer()
            model.closeObscuredPanels()
            model.releaseModifiers()
        }
        if model.keyboardInset != 0 && inset == 0 {
            model.releaseModifiers()
            if !model.isKeyboardPanel { model.closePanel() }
        }
        model.keyboardInset = inset
        surface?.isHidden = !model.active || obscured
        if !obscured && inset == 0 { model.refreshMouseIdleTimer() }
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

    private var mouseAvailable: Bool {
        model.active && !model.functionsOpen && model.sheet == nil &&
            model.keyboardInset <= 0
    }

    private func floatingControl(at point: CGPoint) -> Bool {
        let size = bounds.size
        let controls = [AwesunControlLayout.dockCenter(model.lockPlacement, in: size)] +
            (0..<3).map { AwesunControlLayout.rail($0, in: size) }
        return controls.contains {
            AwesunControlLayout.circle(point, at: $0, radius: AwesunControlLayout.controlRadius)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !isHidden && isUserInteractionEnabled && bounds.contains(point) &&
            mouseAvailable && !floatingControl(at: point),
            AwesunControlLayout.mouseRegion(point, model: model, size: bounds.size) != nil {
            if mouseInput.canStart { return mouseInput }
            return nil
        }
        return super.hitTest(point, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        if model.functionsOpen || (model.sheet != nil &&
            !(model.isKeyboardPanel && model.keyboardInset > 0)) { return true }

        let size = bounds.size
        if model.keyboardInset > 0 {
            return (size.height - model.keyboardInset - 38 ... size.height - model.keyboardInset).contains(point.y)
        }
        if model.mouseVisible && model.mouseCollapsed &&
            AwesunControlLayout.circle(point, at: AwesunControlLayout.dockCenter(model.mousePlacement, in: size),
                                       radius: AwesunControlLayout.controlRadius) {
            return true
        }
        return floatingControl(at: point)
    }
}

private final class AwesunMouseInput: UIView {
    private weak var surface: AwesunTouchSurface?
    private var contact: UITouch?
    private var region: AwesunMouseRegion?
    private var start: CGPoint = .zero
    private var previous: CGPoint = .zero
    private var moved = false
    private let dragThreshold: CGFloat = 5
    private var hubTap: Task<Void, Never>?
    private var wheelAngle: Double?
    private var wheelRemainder = 0.0

    init(surface: AwesunTouchSurface) {
        self.surface = surface
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { nil }

    // The surface routes only the drawn controls here. Other touches reach Flutter.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    var canStart: Bool { contact == nil }

    private func pointer(_ surface: AwesunTouchSurface) -> CGPoint {
        AwesunControlLayout.pointer(surface.model.mouseAnchor, in: bounds.size,
                                   viewport: surface.model.mouseViewport)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard contact == nil, let touch = touches.first, let surface = surface else { return }
        let point = touch.location(in: self)
        guard let hit = AwesunControlLayout.mouseRegion(point, model: surface.model, size: bounds.size)
        else { return }
        contact = touch
        region = hit
        start = point
        previous = point
        moved = false
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
        guard let touch = contact, touches.contains(touch),
              let region = region, let surface = surface else { return }
        let current = touch.location(in: self)
        let distance = hypot(current.x - start.x, current.y - start.y)
        let wasMoved = moved
        moved = moved || distance >= dragThreshold
        switch region {
        case .left, .hub:
            if moved {
                hubTap?.cancel()
                hubTap = nil
                let origin = wasMoved ? previous : start
                let old = AwesunControlLayout.mouseAnchor(surface.model.mouseAnchor, in: bounds.size)
                let next = CGPoint(x: old.x + current.x - origin.x, y: old.y + current.y - origin.y)
                let anchor = AwesunControlLayout.mouseAnchor(next, in: bounds.size)
                let target = AwesunControlLayout.pointer(anchor, in: bounds.size,
                                                         viewport: surface.model.mouseViewport)
                surface.model.moveVirtualPointer(anchor: anchor, point: target)
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
        previous = current
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = contact, touches.contains(touch),
              let region = region, let surface = surface else { return }
        let model = surface.model
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
                        !model.functionsOpen && model.sheet == nil && model.keyboardInset <= 0 {
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
    }

    func cancel() {
        hubTap?.cancel()
        hubTap = nil
        if contact != nil { finish() }
    }

    private func finish() {
        let temporaryWheel = region == .wheelTop
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

    private func updateWheel(at point: CGPoint) {
        guard let surface = surface else { return }
        let center = AwesunControlLayout.mouseCenter(
            surface.model.mouseAnchor, in: bounds.size, viewport: surface.model.mouseViewport)
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard hypot(dx, dy) >= AwesunControlLayout.ringRadius / 2 else {
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
