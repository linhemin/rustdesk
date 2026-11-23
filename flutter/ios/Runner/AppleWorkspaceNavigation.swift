import Flutter
import UIKit
import SwiftUI

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
        if (args as? [String: Any])?["quickConnect"] is String {
            return WorkspaceQuickConnectDock(arguments: args, channel: channel)
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), (args as? [String: Any])?["compact"] as? Bool == true {
            return SystemWorkspaceTabView(frame: frame, arguments: args, channel: channel)
        }
        #endif
        return AppleWorkspaceTabBar(frame: frame, arguments: args, channel: channel)
    }
}

private final class WorkspaceQuickConnectDock: NSObject, FlutterPlatformView {
    private let channel: FlutterMethodChannel
    private let controller: UIHostingController<WorkspaceDockContent>

    init(arguments: Any?, channel: FlutterMethodChannel) {
        self.channel = channel
        controller = UIHostingController(rootView: WorkspaceDockContent(
            arguments: arguments, onSelect: { channel.invokeMethod("select", arguments: $0) },
            onQuickConnect: { channel.invokeMethod("quickConnect", arguments: nil) }
        ))
        super.init()
        controller.view.backgroundColor = .clear
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

    deinit { channel.setMethodCallHandler(nil) }

    func view() -> UIView { controller.view }

    private func update(_ arguments: Any?) {
        guard let config = WorkspaceTabConfiguration(arguments) else { return }
        controller.overrideUserInterfaceStyle = config.appearance
        controller.rootView = WorkspaceDockContent(
            arguments: arguments, onSelect: { [channel] in
                channel.invokeMethod("select", arguments: $0)
            }, onQuickConnect: { [channel] in
                channel.invokeMethod("quickConnect", arguments: nil)
            }
        )
    }
}

private struct WorkspaceDockContent: View {
    let arguments: Any?
    let onSelect: (Int) -> Void
    let onQuickConnect: () -> Void

    var body: some View {
        if let settings = WorkspaceTabConfiguration(arguments) {
            content(settings)
        }
    }

    private func content(_ settings: WorkspaceTabConfiguration) -> some View {
        let options = arguments as? [String: Any] ?? [:]
        let textScale = options["textScale"] as? Double ?? 1
        let rtl = options["rtl"] as? Bool ?? false
        let dark = settings.appearance == .dark
        return HStack(spacing: 10) {
            GeometryReader { bounds in
            HStack(spacing: 0) {
                ForEach(settings.labels.indices, id: \.self) { index in
                    let selected = settings.selected == index
                    Button { onSelect(index) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: settings.symbols[index])
                                .font(.system(size: 18, weight: .medium))
                            Text(settings.labels[index])
                                .font(.system(size: 10 * textScale, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundColor(selected ? Color(settings.accent) : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LinearGradient(
                            colors: dark ? [.white.opacity(0.19), .white.opacity(0.08)]
                                : [.white.opacity(0.95), Color(red: 235 / 255, green: 242 / 255, blue: 1).opacity(0.72)],
                            startPoint: .top, endPoint: .bottom
                        ).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.45), .clear],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 1))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        .opacity(selected ? 1 : 0))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.labels[index])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .workspaceDockGlass(Capsule(), dark: dark)
            .contentShape(Capsule())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onEnded { value in
                guard bounds.size.width > 8, !settings.labels.isEmpty,
                      CGRect(origin: .zero, size: bounds.size).contains(value.location) else { return }
                let width = (bounds.size.width - 8) / CGFloat(settings.labels.count)
                let column = min(settings.labels.count - 1, max(0, Int((value.location.x - 4) / width)))
                onSelect(rtl ? settings.labels.count - 1 - column : column)
            })
            }
            Button(action: onQuickConnect) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(Color(settings.accent))
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .workspaceDockGlass(Circle(), dark: dark)
            .accessibilityLabel(options["quickConnect"] as? String ?? "Connect")
        }
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .environment(\.colorScheme, settings.appearance == .dark ? .dark : .light)
        .ignoresSafeArea()
    }
}

private extension View {
    @ViewBuilder
    func workspaceDockGlass<S: InsettableShape>(_ shape: S, dark: Bool) -> some View {
        let surface = self.background(LinearGradient(
            colors: dark
                ? [Color(red: 46 / 255, green: 54 / 255, blue: 70 / 255).opacity(0.62),
                   Color(red: 22 / 255, green: 26 / 255, blue: 36 / 255).opacity(0.72)]
                : [.white.opacity(0.78),
                   Color(red: 242 / 255, green: 245 / 255, blue: 252 / 255).opacity(0.68)],
            startPoint: .top, endPoint: .bottom
        ), in: shape)
        Group {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            surface.glassEffect(.regular.interactive(), in: shape)
        } else {
            surface.background(.ultraThinMaterial, in: shape)
        }
        #else
        surface.background(.ultraThinMaterial, in: shape)
        #endif
        }
        .overlay(shape.strokeBorder(.white.opacity(dark ? 0.22 : 0.85), lineWidth: 1)
            .allowsHitTesting(false))
        .overlay(shape.inset(by: 1).strokeBorder(LinearGradient(
            colors: [.white.opacity(dark ? 0.30 : 0.95),
                     (dark ? .black : Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255))
                        .opacity(dark ? 0.35 : 0.08)],
            startPoint: .top, endPoint: .bottom
        ), lineWidth: dark ? 1 : 1.5).allowsHitTesting(false))
    }
}

private struct WorkspaceTabConfiguration {
    let labels: [String]
    let symbols: [String]
    let selected: Int
    let appearance: UIUserInterfaceStyle
    var accent: UIColor {
        appearance == .dark
            ? UIColor(red: 76 / 255, green: 139 / 255, blue: 245 / 255, alpha: 1)
            : UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
    }

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
        tabBar.tintColor = settings.accent
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
        root.controller.tabBar.tintColor = settings.accent
        if labels != settings.labels || symbols != settings.symbols {
            labels = settings.labels
            symbols = settings.symbols
            root.controller.setItems(labels: labels, symbols: symbols, selected: settings.selected)
        } else {
            root.controller.select(settings.selected)
        }
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

    func setItems(labels: [String], symbols: [String], selected: Int) {
        // UIKit auto-selects the first tab when replacing the list.
        delegate = nil
        defer { delegate = self }
        mode = .tabBar
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
        select(selected)
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
