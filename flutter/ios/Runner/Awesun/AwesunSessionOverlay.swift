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
                self.savePhoto(call.arguments as? FlutterStandardTypedData, result: result)
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
    }

    private func setActive(_ active: Bool, touchMode: Bool) -> Bool {
        guard let host = host, let surface = surface else { return false }
        if !active && model.active {
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
            model.endDrag()
            model.pauseMouseIdleTimer()
            model.closePanel()
            model.closeKeyboard()
        }
        if model.keyboardInset != 0 && inset == 0 {
            model.releaseModifiers()
            model.closePanel()
        }
        model.keyboardInset = inset
        surface?.isHidden = !model.active || obscured
        if !obscured && inset == 0 { model.refreshMouseIdleTimer() }
    }

    private func savePhoto(_ png: FlutterStandardTypedData?, result: @escaping FlutterResult) {
        guard let data = png?.data, !data.isEmpty else { result("encodeFailed"); return }
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

    init(model: AwesunSessionModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        if model.functionsOpen || model.sheet != nil { return true }

        let size = bounds.size
        if model.keyboardInset > 0 {
            return (size.height - model.keyboardInset - 38 ... size.height - model.keyboardInset).contains(point.y)
        }
        if model.keyboardOpen {
            return point.y >= size.height - AwesunControlLayout.keyboardHeight(in: size)
        }

        if model.mouseVisible && AwesunControlLayout.mouseHit(point, model: model, size: size) {
            return true
        }
        if AwesunControlLayout.circle(point, at: AwesunControlLayout.lock(in: size), radius: 20) {
            return true
        }
        return (0..<3).contains { index in
            AwesunControlLayout.circle(point, at: AwesunControlLayout.rail(index, in: size), radius: 20)
        }
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
