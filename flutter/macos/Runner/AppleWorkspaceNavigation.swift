import AppKit
import FlutterMacOS

final class AppleWorkspaceNavigationFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    static func register(with registrar: FlutterPluginRegistrar) {
        registrar.register(
            AppleWorkspaceNavigationFactory(messenger: registrar.messenger),
            withId: "rustdesk/apple_workspace_navigation"
        )
    }

    private init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        AppleWorkspaceSidebar(viewId: viewId, arguments: args, messenger: messenger)
    }
}

private final class AppleWorkspaceSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let brand = NSTextField(labelWithString: "")
    private let settingsButton = NSButton()
    private let separator = NSBox()
    private let channel: FlutterMethodChannel
    private var listHeight: NSLayoutConstraint!
    private var labels: [String] = []
    private var symbols: [String] = []
    private var applyingConfiguration = false

    init(viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "rustdesk/apple_workspace_navigation/\(viewId)", binaryMessenger: messenger
        )
        super.init(frame: .zero)

        let content = NSView()
        let surface = Self.makeSurface(content)
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        let mark = NSImageView()
        mark.image = Self.appMark()
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.setAccessibilityElement(false)
        brand.font = .systemFont(ofSize: 17, weight: .semibold)
        brand.lineBreakMode = .byTruncatingTail
        brand.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [mark, brand])
        header.spacing = 9
        header.alignment = .centerY

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("destination"))
        column.minWidth = 1
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.backgroundColor = .clear
        table.autoresizingMask = [.width]
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = NSSize(width: 0, height: 3)
        if #available(macOS 11.0, *) { table.style = .plain }
        table.delegate = self
        table.dataSource = self

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = table
        separator.boxType = .separator
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.alignment = .left
        settingsButton.imagePosition = .imageLeading
        settingsButton.image = Self.symbol("slider.horizontal.3")
        settingsButton.font = .systemFont(ofSize: 13)
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)

        let edge = NSBox()
        edge.boxType = .separator
        for item in [header, scroll, separator, settingsButton, edge] as [NSView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(item)
        }
        listHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            mark.widthAnchor.constraint(equalToConstant: 25),
            mark.heightAnchor.constraint(equalToConstant: 25),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 22),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            listHeight,
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            separator.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            separator.heightAnchor.constraint(equalToConstant: 1),
            settingsButton.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            settingsButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            settingsButton.heightAnchor.constraint(equalToConstant: 33),
            edge.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            edge.topAnchor.constraint(equalTo: content.topAnchor),
            edge.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1)
        ])

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

    required init?(coder: NSCoder) { nil }

    deinit { channel.setMethodCallHandler(nil) }

    private static func makeSurface(_ content: NSView) -> NSView {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 0
            glass.contentView = content
            return glass
        }
#endif
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .withinWindow
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        return material
    }

    private static func appMark() -> NSImage? {
        if let frameworks = Bundle.main.privateFrameworksURL,
           let assets = Bundle(url: frameworks.appendingPathComponent("App.framework")) {
            for ext in ["png", "svg"] {
                if let url = assets.url(forResource: "icon", withExtension: ext,
                                        subdirectory: "flutter_assets/assets"),
                   let mark = NSImage(contentsOf: url) { return mark }
            }
        }
        return NSApp.applicationIconImage
    }

    private static func symbol(_ name: String) -> NSImage? {
        if #available(macOS 11.0, *) {
            let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "display", accessibilityDescription: nil)
            return icon?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        }
        return NSImage(named: NSImage.actionTemplateName)
    }

    @objc private func openSettings() {
        channel.invokeMethod("settings", arguments: nil)
    }

    private func update(_ arguments: Any?) {
        guard let config = arguments as? [String: Any],
              let labels = config["labels"] as? [String],
              let symbols = config["symbols"] as? [String],
              labels.count == symbols.count,
              let selected = config["selected"] as? Int else { return }

        applyingConfiguration = true
        defer { applyingConfiguration = false }
        appearance = NSAppearance(named: config["dark"] as? Bool == true ? .darkAqua : .aqua)
        brand.stringValue = config["brand"] as? String ?? ""
        settingsButton.title = config["settings"] as? String ?? ""
        settingsButton.isHidden = settingsButton.title.isEmpty
        separator.isHidden = settingsButton.isHidden
        table.rowHeight = config["compact"] as? Bool == true ? 32 : 35
        listHeight.constant = CGFloat(labels.count) * (table.rowHeight + table.intercellSpacing.height)
        if self.labels != labels || self.symbols != symbols {
            self.labels = labels
            self.symbols = symbols
            table.reloadData()
        }
        if labels.indices.contains(selected) {
            table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { labels.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WorkspaceDestinationRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let title = NSTextField(labelWithString: labels[row])
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let icon = NSImageView()
        icon.image = Self.symbol(symbols[row])
        icon.setAccessibilityElement(false)
        let stack = NSStackView(views: [icon, title])
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.textField = title
        cell.imageView = icon
        cell.toolTip = labels[row]
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingConfiguration, labels.indices.contains(table.selectedRow) else { return }
        channel.invokeMethod("select", arguments: table.selectedRow)
    }
}

private final class WorkspaceDestinationRow: NSTableRowView {
    private var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func drawSelection(in dirtyRect: NSRect) {
        let color = dark ? NSColor(srgbRed: 0.19, green: 0.24, blue: 0.38, alpha: 1)
                         : NSColor(srgbRed: 0.92, green: 0.93, blue: 0.99, alpha: 1)
        color.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0), xRadius: 8, yRadius: 8).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override var isSelected: Bool { didSet { updateForeground() } }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        updateForeground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateForeground()
        needsDisplay = true
    }

    private func updateForeground() {
        guard let cell = subviews.compactMap({ $0 as? NSTableCellView }).first else { return }
        let foreground = dark ? NSColor(srgbRed: 0.78, green: 0.82, blue: 1, alpha: 1)
                              : NSColor(srgbRed: 0.20, green: 0.28, blue: 0.70, alpha: 1)
        cell.textField?.textColor = isSelected ? foreground : .labelColor
        cell.textField?.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
        cell.imageView?.contentTintColor = isSelected ? foreground : .secondaryLabelColor
    }
}
