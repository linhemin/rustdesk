import Flutter
import UIKit

final class AppleWorkspaceNavigationFactory: NSObject, FlutterPlatformViewFactory {
    private static let viewType = "rustdesk/apple_workspace_navigation"
    private let messenger: FlutterBinaryMessenger

    static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        FlutterMethodChannel(name: "\(viewType)/layout", binaryMessenger: messenger)
            .setMethodCallHandler { call, result in
                guard call.method == "usesSystemTabs" else {
                    result(FlutterMethodNotImplemented)
                    return
                }
                #if compiler(>=6.2)
                if #available(iOS 26.0, *) {
                    result(true)
                    return
                }
                #endif
                result(false)
            }
        registrar.register(
            AppleWorkspaceNavigationFactory(messenger: messenger),
            withId: viewType
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
        let channel = FlutterMethodChannel(name: "\(Self.viewType)/\(viewId)", binaryMessenger: messenger)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), (args as? [String: Any])?["compact"] as? Bool == true {
            return SystemWorkspaceTabView(frame: frame, arguments: args, channel: channel)
        }
        #endif
        return AppleWorkspaceTabBar(frame: frame, arguments: args, channel: channel)
    }
}

private struct WorkspaceTabConfiguration {
    let labels: [String]
    let symbols: [String]
    let selected: Int
    let appearance: UIUserInterfaceStyle

    init?(_ arguments: Any?) {
        guard let settings = arguments as? [String: Any],
              let labels = settings["labels"] as? [String],
              let symbols = settings["symbols"] as? [String],
              labels.count == symbols.count,
              let selected = settings["selected"] as? Int else { return nil }
        self.labels = labels
        self.symbols = symbols
        self.selected = selected
        appearance = settings["dark"] as? Bool == true ? .dark : .light
    }
}

private final class AppleWorkspaceTabBar: NSObject, FlutterPlatformView, UITabBarDelegate {
    private let root: UIView
    private let tabBar = UITabBar()
    private let channel: FlutterMethodChannel
    private var labels: [String] = []
    private var symbols: [String] = []

    init(frame: CGRect, arguments: Any?, channel: FlutterMethodChannel) {
        let compact = (arguments as? [String: Any])?["compact"] as? Bool == true
        root = UIView(frame: frame)
        self.channel = channel
        super.init()
        root.backgroundColor = .clear
        root.isOpaque = false
        tabBar.delegate = self
        if #unavailable(iOS 26) {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.shadowColor = .clear
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
        if compact {
            tabBar.itemPositioning = .fill
            let scrub = UILongPressGestureRecognizer(target: self, action: #selector(releaseTab(_:)))
            scrub.minimumPressDuration = 0.25
            tabBar.addGestureRecognizer(scrub)
        }
        pin(tabBar, inside: root)
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
        guard let settings = WorkspaceTabConfiguration(arguments) else { return }
        let labels = settings.labels
        let symbols = settings.symbols
        let selected = settings.selected

        root.overrideUserInterfaceStyle = settings.appearance
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

    @objc private func releaseTab(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: tabBar)
        guard gesture.state == .ended, let items = tabBar.items, !items.isEmpty,
              tabBar.bounds.width > 0, tabBar.bounds.contains(point) else { return }
        let column = min(items.count - 1, Int(point.x / tabBar.bounds.width * CGFloat(items.count)))
        let index = tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? items.count - 1 - column : column
        guard tabBar.selectedItem !== items[index] else { return }
        tabBar.selectedItem = items[index]
        channel.invokeMethod("select", arguments: index)
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        channel.invokeMethod("select", arguments: item.tag)
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private final class SystemWorkspaceTabView: NSObject, FlutterPlatformView {
    private let root: SystemWorkspaceTabHost
    private let channel: FlutterMethodChannel
    private var labels: [String] = []
    private var symbols: [String] = []

    init(frame: CGRect, arguments: Any?, channel: FlutterMethodChannel) {
        root = SystemWorkspaceTabHost(frame: frame)
        self.channel = channel
        super.init()
        root.backgroundColor = .clear
        root.isOpaque = false
        root.controller.onSelect = { [weak self] index in
            self?.channel.invokeMethod("select", arguments: index)
        }
        root.controller.onHeightChange = { [weak self] height in
            self?.channel.invokeMethod("systemHeight", arguments: Double(height))
        }
        update(arguments)
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self?.update(call.arguments)
            result(self?.root.controller.reportedHeight.map { Double($0) })
        }
    }

    deinit {
        channel.setMethodCallHandler(nil)
    }

    func view() -> UIView { root }

    private func update(_ arguments: Any?) {
        guard let settings = WorkspaceTabConfiguration(arguments) else { return }
        root.overrideUserInterfaceStyle = settings.appearance
        if labels != settings.labels || symbols != settings.symbols {
            labels = settings.labels
            symbols = settings.symbols
            root.controller.setItems(labels: labels, symbols: symbols)
        }
        root.controller.select(settings.selected)
    }
}

@available(iOS 26.0, *)
private final class SystemWorkspaceTabHost: UIView {
    let controller = SystemWorkspaceTabs()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // A platform view is inserted into Flutter's view hierarchy after creation.
        var responder = superview?.next
        while responder != nil && !(responder is UIViewController) {
            responder = responder?.next
        }
        let parent = window == nil ? nil : responder as? UIViewController
        guard controller.parent !== parent else { return }
        if controller.parent != nil {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        guard let parent else { return }
        parent.addChild(controller)
        controller.view.frame = bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(controller.view)
        controller.didMove(toParent: parent)
    }
}

@available(iOS 26.0, *)
private final class SystemWorkspaceTabs: UITabBarController, UITabBarControllerDelegate {
    var onSelect: ((Int) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    private(set) var reportedHeight: CGFloat?
    private var selectedIndexFromFlutter: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        tabBarMinimizeBehavior = .never
    }

    func setItems(labels: [String], symbols: [String]) {
        mode = .tabBar
        delegate = self
        setTabs(labels.enumerated().map { index, label in
            UITab(
                title: label,
                image: UIImage(systemName: symbols[index]) ?? UIImage(systemName: "circle"),
                identifier: String(index)
            ) { _ in
                let content = UIViewController()
                // Flutter owns the page below the bar, including its background and input.
                content.view.backgroundColor = .clear
                content.view.isOpaque = false
                content.view.isUserInteractionEnabled = false
                return content
            }
        }, animated: false)
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndexFromFlutter = index
        if selectedTab !== tabs[index] {
            selectedTab = tabs[index]
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController, didSelectTab tab: UITab, previousTab: UITab?
    ) {
        // UIKit performs its own Liquid Glass scrub and commits the tab on release.
        guard let index = tabs.firstIndex(where: { $0 === tab }),
              index != selectedIndexFromFlutter else { return }
        selectedIndexFromFlutter = index
        onSelect?(index)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.window != nil else { return }
        let frame = tabBar.convert(tabBar.bounds, to: view)
        guard !frame.isEmpty, frame.minY >= 0, frame.minY < view.bounds.maxY else { return }
        let height = ceil(view.bounds.maxY - frame.minY)
        guard height != reportedHeight else { return }
        reportedHeight = height
        onHeightChange?(height)
    }
}
#endif
