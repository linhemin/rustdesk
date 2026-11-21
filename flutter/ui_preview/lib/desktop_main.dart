import 'package:flutter/material.dart';
import 'package:rustdesk_ui/desktop.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

void main() => runApp(const DesktopRuntimePreview());

/// Sample-data catalog of desktop chrome, never a remote-session implementation.
class DesktopRuntimePreview extends StatefulWidget {
  const DesktopRuntimePreview({super.key});

  @override
  State<DesktopRuntimePreview> createState() => _DesktopRuntimePreviewState();
}

class _DesktopRuntimePreviewState extends State<DesktopRuntimePreview> {
  bool dark = false;
  bool files = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: WorkspaceStyle.apply(ThemeData(useMaterial3: false)),
        darkTheme: WorkspaceStyle.apply(ThemeData.dark(useMaterial3: false)),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: const Text('RustDesk / Desktop UI catalog',
                style: TextStyle(fontSize: 16)),
            actions: [
              TextButton.icon(
                  onPressed: () => setState(() => files = !files),
                  icon: Icon(files ? Icons.desktop_windows : Icons.folder_open),
                  label: Text(files ? 'Remote session' : 'File transfer')),
              IconButton(
                  tooltip: dark ? 'Light appearance' : 'Dark appearance',
                  onPressed: () => setState(() => dark = !dark),
                  icon: Icon(dark ? Icons.light_mode : Icons.dark_mode)),
              const SizedBox(width: 16),
            ],
          ),
          body: Column(children: [
            Expanded(
                child:
                    files ? const TransferPreview() : const SessionPreview()),
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                  'UI catalog · Sample data only · No remote connection or file access',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11)),
            ),
          ]),
        ),
      );
}

class SessionPreview extends StatefulWidget {
  const SessionPreview({super.key});

  @override
  State<SessionPreview> createState() => _SessionPreviewState();
}

class _SessionPreviewState extends State<SessionPreview> {
  bool collapsed = false;
  bool quality = true;
  bool chat = false;
  bool pinned = true;
  bool recording = false;
  bool bottom = false;
  String scale = 'Fit to window';

  Widget action(String label, IconData icon, VoidCallback onPressed,
          {bool active = false, bool destructive = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: SizedBox.square(
          dimension: DesktopSessionStyle.buttonSize,
          child: Tooltip(
            message: label,
            child: Material(
              borderRadius:
                  BorderRadius.circular(DesktopSessionStyle.buttonRadius),
              color: destructive
                  ? const Color(0xFFE4556C)
                  : active
                      ? WorkspaceStyle.accent
                      : DesktopSessionStyle.inactive,
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(DesktopSessionStyle.buttonRadius),
                onTap: onPressed,
                child: Icon(icon, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      );

  Widget menu(String label, IconData icon, List<Widget> children) => MenuAnchor(
        style: DesktopSessionStyle.menuStyle(context),
        menuChildren: children,
        builder: (context, controller, child) => action(label, icon, () {
          controller.isOpen ? controller.close() : controller.open();
        }),
      );

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF34476C),
                  Color(0xFF17243C),
                  Color(0xFF42676E)
                ],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(44, 100, 44, 80),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: WorkspacePanel(
                    padding: EdgeInsets.zero,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(children: [
                          for (final color in [
                            Colors.redAccent,
                            Colors.amber,
                            Colors.green
                          ])
                            Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child:
                                    Icon(Icons.circle, size: 10, color: color)),
                          const SizedBox(width: 12),
                          const Expanded(
                              child: Text('Studio Mac / sample desktop')),
                          const Icon(Icons.lock_outline, size: 16),
                        ]),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const WorkspaceIcon(
                                  icon: Icons.auto_awesome_rounded, size: 56),
                              const SizedBox(height: 24),
                              Text('A little closer.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 12),
                              Text('Your work, wherever you are.',
                                  style: TextStyle(
                                      color: Theme.of(context).hintColor)),
                              const SizedBox(height: 32),
                              Wrap(spacing: 16, runSpacing: 16, children: [
                                for (final item in [
                                  'Projects',
                                  'Documents',
                                  'Design assets'
                                ])
                                  SizedBox(
                                      width: 140,
                                      child: WorkspacePanel(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.folder_outlined,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary),
                                              const SizedBox(height: 12),
                                              Text(item),
                                            ]),
                                      )),
                              ]),
                            ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: bottom ? null : 12,
          bottom: bottom ? 12 : null,
          left: 16,
          right: 16,
          child: Center(
            child: collapsed
                ? SessionToolbarSurface(
                    child: action('Show toolbar', Icons.expand_more,
                        () => setState(() => collapsed = false)))
                : SessionToolbarSurface(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(width: 6),
                        action(
                            'Pin toolbar',
                            pinned ? Icons.push_pin : Icons.push_pin_outlined,
                            () => setState(() => pinned = !pinned),
                            active: pinned),
                        menu('Session controls', Icons.tune_rounded, [
                          MenuItemButton(
                              onPressed: () => setState(() => bottom = !bottom),
                              leadingIcon:
                                  const Icon(Icons.vertical_align_bottom),
                              child: Text(
                                  bottom ? 'Dock at top' : 'Dock at bottom')),
                          MenuItemButton(
                              onPressed: () => setState(() => collapsed = true),
                              leadingIcon: const Icon(Icons.unfold_less),
                              child: const Text('Hide toolbar')),
                        ]),
                        menu(
                            'Display options', Icons.desktop_windows_outlined, [
                          for (final option in [
                            'Fit to window',
                            'Original size'
                          ])
                            MenuItemButton(
                                onPressed: () => setState(() => scale = option),
                                leadingIcon: Icon(
                                    scale == option
                                        ? Icons.check
                                        : Icons.crop_free,
                                    size: 18),
                                child: Text(option)),
                          const Divider(),
                          MenuItemButton(
                              onPressed: () =>
                                  setState(() => quality = !quality),
                              leadingIcon: Icon(quality
                                  ? Icons.check_box_outlined
                                  : Icons.check_box_outline_blank),
                              child: const Text('Quality monitor')),
                        ]),
                        menu('Keyboard', Icons.keyboard_outlined, [
                          MenuItemButton(
                              onPressed: () => ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(
                                      content: Text(
                                          'Preview only — no keys are sent.'))),
                              child: const Text('Insert Ctrl + Alt + Del')),
                        ]),
                        action('Chat', Icons.chat_bubble_outline,
                            () => setState(() => chat = !chat),
                            active: chat),
                        action(
                            'Record preview',
                            Icons.fiber_manual_record_outlined,
                            () => setState(() => recording = !recording),
                            active: recording),
                        action('Close preview toolbar', Icons.close,
                            () => setState(() => collapsed = true),
                            destructive: true),
                        const SizedBox(width: 6),
                      ]),
                    ),
                  ),
          ),
        ),
        if (quality)
          Positioned(
              top: 84,
              right: 20,
              child: SessionOverlayFrame(
                child: Container(
                  width: 192,
                  padding: const EdgeInsets.all(14),
                  color: const Color(0xEB17233B),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('QUALITY / SAMPLE',
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1,
                                color: Color(0xFFA5B4FC))),
                        const SizedBox(height: 10),
                        for (final stat in [
                          ('Speed', '1.8 MB/s'),
                          ('FPS', '60'),
                          ('Delay', '24 ms'),
                          ('Codec', 'H.264')
                        ])
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(stat.$1,
                                        style: const TextStyle(
                                            color: Color(0xFFB9C6DA),
                                            fontSize: 12)),
                                    Text(stat.$2,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12)),
                                  ])),
                      ]),
                ),
              )),
        if (chat)
          Positioned(
              right: 20,
              bottom: 28,
              child: SizedBox(
                width: 280,
                child: DesktopOverlaySurface(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text('Chat / sample',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium)),
                                IconButton(
                                    tooltip: 'Close chat',
                                    onPressed: () =>
                                        setState(() => chat = false),
                                    icon: const Icon(Icons.close, size: 18))
                              ]),
                              const SizedBox(height: 12),
                              const Text('Messages remain in this UI preview.'),
                              const SizedBox(height: 20),
                              const TextField(
                                  decoration: InputDecoration(
                                      hintText: 'Sample message')),
                            ]))),
              )),
        Positioned(
            left: 20,
            bottom: 20,
            child: Text(
                'Sample canvas · $scale${recording ? ' · Recording indicator demo' : ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ]);
}

class TransferPreview extends StatefulWidget {
  const TransferPreview({super.key});

  @override
  State<TransferPreview> createState() => _TransferPreviewState();
}

class _TransferPreviewState extends State<TransferPreview> {
  String? selected;
  String? transfer;
  bool paused = false;
  bool ascending = true;
  final localScroll = ScrollController();
  final remoteScroll = ScrollController();
  final horizontalScroll = ScrollController();

  @override
  void dispose() {
    localScroll.dispose();
    remoteScroll.dispose();
    horizontalScroll.dispose();
    super.dispose();
  }

  static const entries = [
    ('Design assets', 'Folder', 'Today'),
    ('Documents', 'Folder', 'Yesterday'),
    ('design-system.zip', '24.8 MB', '10:42'),
    ('release-notes.md', '12 KB', '09:16'),
    ('workspace.png', '3.6 MB', 'Yesterday'),
  ];

  Widget browser(bool local) {
    final sorted = ascending ? entries : entries.reversed.toList();
    final scroll = local ? localScroll : remoteScroll;
    return TransferPane(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TransferPaneHeading(
          leading: WorkspaceIcon(
              icon: local
                  ? Icons.laptop_mac_outlined
                  : Icons.desktop_windows_outlined,
              size: 40),
          title: local ? 'Local Computer' : 'Remote Computer'),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.folder_open, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  local
                      ? '/Users/demo/Workspace'
                      : 'C:\\Users\\Demo\\Documents',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)))
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        TextButton.icon(
            onPressed: local && selected != null
                ? () => setState(() {
                      transfer = selected;
                      paused = false;
                    })
                : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(local ? 'Send file' : 'Receive file')),
        const Spacer(),
        IconButton(
            tooltip: local ? 'Sort local files' : 'Sort remote files',
            onPressed: () => setState(() => ascending = !ascending),
            icon: const Icon(Icons.sort_by_alpha, size: 20)),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          Expanded(flex: 3, child: Text('Name')),
          Expanded(child: Text('Size')),
          Expanded(child: Text('Modified'))
        ]),
      ),
      Expanded(
          child: ListView.builder(
        controller: scroll,
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final entry = sorted[index];
          final active = local && selected == entry.$1;
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              color: active ? WorkspaceStyle.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: local ? () => setState(() => selected = entry.$1) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                        color: active ? Colors.white : null, fontSize: 12),
                    child: Row(children: [
                      Expanded(
                          flex: 3,
                          child: Row(children: [
                            Icon(
                                entry.$2 == 'Folder'
                                    ? Icons.folder_outlined
                                    : Icons.insert_drive_file_outlined,
                                size: 18,
                                color: active
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(entry.$1,
                                    overflow: TextOverflow.ellipsis)),
                          ])),
                      Expanded(child: Text(entry.$2)),
                      Expanded(child: Text(entry.$3))
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      )),
      const Divider(),
      Text('${entries.length} items · Sample files',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
    ]));
  }

  Widget queue() => TransferPane(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TransferPaneHeading(
            leading: WorkspaceIcon(icon: Icons.swap_horiz_rounded, size: 36),
            title: 'Transfer file'),
        Expanded(
            child: transfer == null
                ? const TransferEmptyState(message: 'No transfers in progress')
                : Align(
                    alignment: Alignment.topCenter,
                    child: WorkspacePanel(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const WorkspaceIcon(
                                  icon: Icons.upload_file_outlined, size: 36),
                              const SizedBox(height: 16),
                              Text(transfer!,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Text(
                                  paused
                                      ? 'Paused / sample'
                                      : 'In progress / sample',
                                  style: TextStyle(
                                      color: Theme.of(context).hintColor)),
                              const SizedBox(height: 20),
                              LinearProgressIndicator(
                                  value: .62,
                                  backgroundColor:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  color: WorkspaceStyle.accent,
                                  minHeight: 6),
                              const SizedBox(height: 10),
                              const Text('62% · Simulated, no file is sent',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(height: 12),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                        tooltip: paused
                                            ? 'Resume preview transfer'
                                            : 'Pause preview transfer',
                                        onPressed: () =>
                                            setState(() => paused = !paused),
                                        icon: Icon(paused
                                            ? Icons.play_arrow
                                            : Icons.pause)),
                                    IconButton(
                                        tooltip: 'Cancel preview transfer',
                                        onPressed: () =>
                                            setState(() => transfer = null),
                                        icon: const Icon(Icons.close)),
                                  ]),
                            ])),
                  )),
      ]));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
            controller: horizontalScroll,
            thumbVisibility: constraints.maxWidth < 1120,
            child: SingleChildScrollView(
              controller: horizontalScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width:
                    constraints.maxWidth < 1120 ? 1120 : constraints.maxWidth,
                height: constraints.maxHeight,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: browser(true)),
                      Expanded(flex: 3, child: browser(false)),
                      Expanded(flex: 2, child: queue()),
                    ]),
              ),
            ),
          ));
}
