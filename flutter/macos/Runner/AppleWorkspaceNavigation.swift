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
    private let settingsTopInset: CGFloat = 16
    private let channel: FlutterMethodChannel
    private var listHeight: NSLayoutConstraint!
    private var labels: [String] = []
    private var symbols: [String] = []
    private var settingsLabel = ""
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
        brand.font = .systemFont(ofSize: 14, weight: .semibold)
        brand.lineBreakMode = .byTruncatingTail
        brand.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [mark, brand])
        header.spacing = 9
        header.alignment = .centerY
        let navigationOnly = (arguments as? [String: Any])?["navigationOnly"] as? Bool == true
        header.isHidden = navigationOnly

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
        if navigationOnly {
            table.target = self
            table.action = #selector(rowClicked)
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = table
        let edge = NSBox()
        edge.boxType = .separator
        for item in [header, scroll, edge] as [NSView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(item)
        }
        listHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        if navigationOnly {
            listHeight.priority = .defaultHigh
            scroll.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor).isActive = true
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
        }
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
            scroll.topAnchor.constraint(equalTo: navigationOnly ? content.topAnchor : header.bottomAnchor,
                                        constant: navigationOnly ? 0 : 22),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            listHeight,
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
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.workspaceSidebar(for: content.effectiveAppearance).cgColor
        return content
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        subviews.first?.layer?.backgroundColor = NSColor.workspaceSidebar(for: effectiveAppearance).cgColor
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
        let settings = config["settings"] as? String ?? ""
        table.rowHeight = config["compact"] as? Bool == true ? 32 : 35
        let rowSpacing = table.rowHeight + table.intercellSpacing.height
        listHeight.constant = CGFloat(labels.count) * rowSpacing
            + (settings.isEmpty ? 0 : rowSpacing + settingsTopInset)
        if self.labels != labels || self.symbols != symbols || settingsLabel != settings {
            self.labels = labels
            self.symbols = symbols
            settingsLabel = settings
            table.reloadData()
        }
        if labels.indices.contains(selected) {
            table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        labels.count + (settingsLabel.isEmpty ? 0 : 1)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        tableView.rowHeight + (row == labels.count ? settingsTopInset : 0)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if row == labels.count && !settingsLabel.isEmpty {
            // Settings opens a separate tab; keep the current home destination selected.
            if !applyingConfiguration {
                channel.invokeMethod("settings", arguments: nil)
            }
            return false
        }
        return true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WorkspaceDestinationRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let settings = row == labels.count
        let title = NSTextField(labelWithString: settings ? settingsLabel : labels[row])
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let icon = NSImageView()
        icon.image = Self.symbol(settings ? "slider.horizontal.3" : symbols[row])
        icon.setAccessibilityElement(false)
        let stack = NSStackView(views: [icon, title])
        stack.spacing = settings ? 5 : 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.textField = title
        cell.imageView = icon
        cell.toolTip = title.stringValue
        cell.addSubview(stack)
        if settings {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                separator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                separator.topAnchor.constraint(equalTo: cell.topAnchor, constant: settingsTopInset / 2),
                separator.heightAnchor.constraint(equalToConstant: 1)
            ])
        }
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: settings ? 15 : 18),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: settings ? settingsTopInset / 2 : 0)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingConfiguration, labels.indices.contains(table.selectedRow) else { return }
        if table.action != nil, let type = NSApp.currentEvent?.type,
           type == .leftMouseDown || type == .leftMouseUp { return }
        channel.invokeMethod("select", arguments: table.selectedRow)
    }

    @objc private func rowClicked() {
        guard !applyingConfiguration, labels.indices.contains(table.clickedRow) else { return }
        channel.invokeMethod("select", arguments: table.clickedRow)
    }
}

private final class WorkspaceDestinationRow: NSTableRowView {
    private var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func drawSelection(in dirtyRect: NSRect) {
        let color = dark ? NSColor(srgbRed: 21 / 255, green: 25 / 255, blue: 33 / 255, alpha: 1)
                         : .white
        color.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0.5), xRadius: 8, yRadius: 8)
        path.fill()
        (dark ? NSColor.white : NSColor(srgbRed: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 1))
            .withAlphaComponent(0.085).setStroke()
        path.lineWidth = 1
        path.stroke()
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
        let accent = dark ? NSColor(srgbRed: 76 / 255, green: 139 / 255, blue: 245 / 255, alpha: 1)
                          : NSColor(srgbRed: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
        let ink = dark ? NSColor(srgbRed: 242 / 255, green: 244 / 255, blue: 248 / 255, alpha: 1)
                       : NSColor(srgbRed: 17 / 255, green: 20 / 255, blue: 26 / 255, alpha: 1)
        let secondary = dark ? NSColor(srgbRed: 154 / 255, green: 163 / 255, blue: 178 / 255, alpha: 1)
                             : NSColor(srgbRed: 87 / 255, green: 96 / 255, blue: 113 / 255, alpha: 1)
        cell.textField?.textColor = isSelected ? ink : secondary
        cell.textField?.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
        cell.imageView?.contentTintColor = isSelected ? accent : secondary
    }
}

private extension NSColor {
    static func workspaceSidebar(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 16 / 255, green: 19 / 255, blue: 25 / 255, alpha: 1)
            : NSColor(srgbRed: 236 / 255, green: 239 / 255, blue: 244 / 255, alpha: 1)
    }
}
