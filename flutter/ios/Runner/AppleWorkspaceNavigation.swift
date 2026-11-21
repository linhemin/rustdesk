import Flutter
import UIKit

final class AppleWorkspaceNavigationFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    static func register(with registrar: FlutterPluginRegistrar) {
        registrar.register(
            AppleWorkspaceNavigationFactory(messenger: registrar.messenger()),
            withId: "rustdesk/apple_workspace_navigation"
        )
    }

    private init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
    ) -> FlutterPlatformView {
        AppleWorkspaceTabBar(frame: frame, viewId: viewId, arguments: args, messenger: messenger)
    }
}

private final class AppleWorkspaceTabBar: NSObject, FlutterPlatformView, UITabBarDelegate {
    private let root: UIView
    private let tabBar = UITabBar()
    private let channel: FlutterMethodChannel
    private var labels: [String] = []
    private var symbols: [String] = []

    init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
        root = UIView(frame: frame)
        channel = FlutterMethodChannel(
            name: "rustdesk/apple_workspace_navigation/\(viewId)", binaryMessenger: messenger
        )
        super.init()
        let content = makeSurface()
        tabBar.delegate = self
        tabBar.isTranslucent = true
        pin(tabBar, inside: content)
        update(arguments)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self?.update(call.arguments)
            result(nil)
        }
    }

    deinit {
        channel.setMethodCallHandler(nil)
    }

    func view() -> UIView { root }

    private func makeSurface() -> UIView {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            let glass = UIVisualEffectView(effect: effect)
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            pin(glass, inside: root)
            return glass.contentView
        }
#endif
        return root
    }

    private func pin(_ child: UIView, inside parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    private func update(_ arguments: Any?) {
        guard let settings = arguments as? [String: Any],
              let labels = settings["labels"] as? [String],
              let symbols = settings["symbols"] as? [String],
              labels.count == symbols.count,
              let selected = settings["selected"] as? Int else { return }

        root.overrideUserInterfaceStyle = settings["dark"] as? Bool == true ? .dark : .light
        tabBar.itemPositioning = settings["compact"] as? Bool == true ? .fill : .automatic
        if self.labels != labels || self.symbols != symbols {
            self.labels = labels
            self.symbols = symbols
            tabBar.items = labels.enumerated().map { index, label in
                UITabBarItem(
                    title: label,
                    image: UIImage(systemName: symbols[index]) ?? UIImage(systemName: "circle"),
                    tag: index
                )
            }
        }
        tabBar.selectedItem = labels.indices.contains(selected) ? tabBar.items?[selected] : nil
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        channel.invokeMethod("select", arguments: item.tag)
    }
}
