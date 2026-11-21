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

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        AppleWorkspaceSidebar(viewId: viewId, arguments: args, messenger: messenger)
    }
}

private final class AppleWorkspaceSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let channel: FlutterMethodChannel
    private var labels: [String] = []
    private var symbols: [String] = []
    private var applyingConfiguration = false

    init(viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "rustdesk/apple_workspace_navigation/\(viewId)", binaryMessenger: messenger
        )
        super.init(frame: .zero)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tab"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.backgroundColor = .clear
        table.autoresizingMask = [.width]
        table.selectionHighlightStyle = .sourceList
        if #available(macOS 11.0, *) {
            table.style = .sourceList
        }
        table.delegate = self
        table.dataSource = self

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table

        let surface = makeSurface(for: scroll)
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
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

    deinit {
        channel.setMethodCallHandler(nil)
    }

    private func makeSurface(for content: NSView) -> NSView {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 20
            glass.contentView = content
            return glass
        }
#endif
        let fallback = NSVisualEffectView()
        fallback.material = .sidebar
        fallback.blendingMode = .withinWindow
        content.frame = fallback.bounds
        content.autoresizingMask = [.width, .height]
        fallback.addSubview(content)
        return fallback
    }

    private func update(_ arguments: Any?) {
        guard let settings = arguments as? [String: Any],
              let labels = settings["labels"] as? [String],
              let symbols = settings["symbols"] as? [String],
              labels.count == symbols.count,
              let selected = settings["selected"] as? Int else { return }

        applyingConfiguration = true
        defer { applyingConfiguration = false }

        appearance = NSAppearance(named: settings["dark"] as? Bool == true ? .darkAqua : .aqua)
        table.rowHeight = settings["compact"] as? Bool == true ? 36 : 42
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

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        let title = NSTextField(labelWithString: labels[row])
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let image = NSImageView()
        if #available(macOS 11.0, *) {
            image.image = NSImage(systemSymbolName: symbols[row], accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        } else {
            image.image = NSImage(named: NSImage.actionTemplateName)
        }
        image.setAccessibilityElement(false)
        image.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let rowContent = NSStackView(views: [image, title])
        rowContent.spacing = 8
        rowContent.alignment = .centerY
        rowContent.translatesAutoresizingMaskIntoConstraints = false

        let cell = NSTableCellView()
        cell.textField = title
        cell.imageView = image
        cell.addSubview(rowContent)
        NSLayoutConstraint.activate([
            rowContent.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            rowContent.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            rowContent.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingConfiguration, labels.indices.contains(table.selectedRow) else { return }
        channel.invokeMethod("select", arguments: table.selectedRow)
    }
}
