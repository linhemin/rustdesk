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
    private let phoneBar: LegacyPhoneWorkspaceTabs?
    private let channel: FlutterMethodChannel
    private var labels: [String] = []
    private var symbols: [String] = []

    init(frame: CGRect, arguments: Any?, channel: FlutterMethodChannel) {
        let compact = (arguments as? [String: Any])?["compact"] as? Bool == true
        root = UIView(frame: frame)
        phoneBar = compact ? LegacyPhoneWorkspaceTabs() : nil
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
        if let phoneBar = phoneBar {
            phoneBar.onSelect = { [weak self] index in
                self?.channel.invokeMethod("select", arguments: index)
            }
            pin(phoneBar, inside: root)
        } else {
            pin(tabBar, inside: root)
        }
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
            if let phoneBar = phoneBar {
                phoneBar.setItems(labels: labels, symbols: symbols)
            } else {
                tabBar.items = labels.enumerated().map { index, label in
                    UITabBarItem(
                        title: label,
                        image: UIImage(systemName: symbols[index]) ?? UIImage(systemName: "circle"),
                        tag: index
                    )
                }
            }
        }
        if let phoneBar = phoneBar {
            phoneBar.select(selected)
        } else {
            tabBar.selectedItem = labels.indices.contains(selected) ? tabBar.items?[selected] : nil
        }
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

private final class LegacyPhoneWorkspaceTabs: UIView {
    var onSelect: ((Int) -> Void)?
    private let glass = UIVisualEffectView()
    private let highlight = UIView()
    private let row = UIStackView()
    private var selected: Int?
    private var scrubX: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        glass.effect = UIBlurEffect(style: .systemChromeMaterial)
        glass.clipsToBounds = true
        addSubview(glass)
        highlight.isUserInteractionEnabled = false
        highlight.backgroundColor = .tertiarySystemFill
        glass.contentView.addSubview(highlight)
        row.distribution = .fillEqually
        glass.contentView.addSubview(row)
        accessibilityTraits = .tabBar
        let scrub = UILongPressGestureRecognizer(target: self, action: #selector(scrubTabs(_:)))
        scrub.minimumPressDuration = 0.25
        addGestureRecognizer(scrub)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setItems(labels: [String], symbols: [String]) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, label) in labels.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.accessibilityLabel = label
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            let icon = UIImageView(image: UIImage(systemName: symbols[index],
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 23, weight: .medium)))
            icon.contentMode = .scaleAspectFit
            let caption = UILabel()
            caption.text = label
            caption.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
                for: .systemFont(ofSize: 11, weight: .semibold))
            caption.adjustsFontForContentSizeCategory = true
            caption.lineBreakMode = .byTruncatingTail
            let stack = UIStackView(arrangedSubviews: [icon, caption])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 4
            stack.isUserInteractionEnabled = false
            stack.accessibilityElementsHidden = true
            stack.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(stack)
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 29),
                icon.heightAnchor.constraint(equalToConstant: 24),
                stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                stack.widthAnchor.constraint(lessThanOrEqualTo: button.widthAnchor, constant: -12),
            ])
            row.addArrangedSubview(button)
        }
        selected = nil
        setNeedsLayout()
    }

    @objc private func tapped(_ button: UIButton) {
        select(button.tag)
        onSelect?(button.tag)
    }

    @objc private func scrubTabs(_ gesture: UILongPressGestureRecognizer) {
        guard let selected = selected else { return }
        let point = gesture.location(in: row)
        switch gesture.state {
        case .began, .changed:
            scrubX = gesture.location(in: glass.contentView).x
            setNeedsLayout()
        case .ended:
            scrubX = nil
            setNeedsLayout()
            if let button = row.arrangedSubviews.first(where: { $0.frame.contains(point) }),
               button.tag != selected {
                select(button.tag)
                onSelect?(button.tag)
            }
        case .cancelled, .failed:
            scrubX = nil
            setNeedsLayout()
        default: break
        }
    }

    func select(_ index: Int) {
        guard selected != index, row.arrangedSubviews.indices.contains(index) else { return }
        let animate = selected != nil && window != nil && !UIAccessibility.isReduceMotionEnabled
        selected = index
        for case let button as UIButton in row.arrangedSubviews {
            let active = button.tag == index
            button.accessibilityTraits = active ? [.button, .selected] : .button
            button.tintColor = active ? .systemBlue : .label
            let stack = button.subviews.compactMap { $0 as? UIStackView }.first
            (stack?.arrangedSubviews.last as? UILabel)?.textColor = button.tintColor
        }
        setNeedsLayout()
        if animate {
            UIView.animate(withDuration: 0.22, delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.layoutIfNeeded()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        glass.layer.cornerRadius = bounds.height / 2
        row.frame = bounds.insetBy(dx: 5, dy: 0)
        row.layoutIfNeeded()
        guard let index = selected, row.arrangedSubviews.indices.contains(index) else { return }
        let button = row.arrangedSubviews[index]
        let contentWidth = button.subviews.compactMap { $0 as? UIStackView }.first?.bounds.width ?? 0
        let width = min(button.bounds.width, max(80, contentWidth + 28))
        let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY),
                                    to: glass.contentView)
        let x = scrubX.map { min(max(row.frame.minX + width / 2, $0), row.frame.maxX - width / 2) } ?? center.x
        highlight.frame = CGRect(x: x - width / 2, y: 4, width: width,
                                 height: max(0, bounds.height - 8))
        highlight.layer.cornerRadius = highlight.bounds.height / 2
    }
}
