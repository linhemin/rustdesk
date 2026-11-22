import 'package:flutter/material.dart';

import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:rustdesk_ui/workspace_navigation.dart';

void main() => runApp(const RustDeskPreview());

/// A visual catalog, not a replacement runtime: all data stays in this process.
class RustDeskPreview extends StatefulWidget {
  const RustDeskPreview({super.key});

  @override
  State<RustDeskPreview> createState() => _RustDeskPreviewState();
}

class _RustDeskPreviewState extends State<RustDeskPreview> {
  bool dark = false;
  bool mobile = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RustDesk UI preview',
        theme: WorkspaceStyle.apply(ThemeData(useMaterial3: false)),
        darkTheme: WorkspaceStyle.apply(ThemeData.dark(useMaterial3: false)),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Builder(builder: (context) {
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 44,
              title: const Text('RustDesk / UI preview',
                  style: TextStyle(fontSize: 14)),
              actions: [
                IconButton(
                  tooltip: mobile ? 'Desktop layout' : 'Phone layout',
                  onPressed: () => setState(() => mobile = !mobile),
                  icon: Icon(mobile
                      ? Icons.desktop_windows_outlined
                      : Icons.phone_iphone_rounded),
                ),
                IconButton(
                  tooltip: dark ? 'Light appearance' : 'Dark appearance',
                  onPressed: () => setState(() => dark = !dark),
                  icon: Icon(dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                ),
                const SizedBox(width: 12),
              ],
            ),
            body: Center(
              child: Container(
                constraints:
                    BoxConstraints(maxWidth: mobile ? 390 : double.infinity),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: mobile
                      ? Border.symmetric(
                          vertical:
                              BorderSide(color: Theme.of(context).dividerColor))
                      : null,
                ),
                child: const PreviewWorkspace(),
              ),
            ),
          );
        }),
      );
}

class PreviewWorkspace extends StatefulWidget {
  const PreviewWorkspace({super.key});

  @override
  State<PreviewWorkspace> createState() => _PreviewWorkspaceState();
}

class _PreviewWorkspaceState extends State<PreviewWorkspace> {
  int selected = 0;
  int mode = 0;
  bool notifications = true;
  bool clipboard = true;
  String query = '';
  final remoteId = TextEditingController();
  final form = GlobalKey<FormState>();

  static const devices = [
    ('Studio Mac', 'macOS · 842 193 506', Icons.laptop_mac_rounded, true),
    (
      'Office workstation',
      'Windows · 625 048 319',
      Icons.desktop_windows_rounded,
      true
    ),
    ('Living room PC', 'Windows · 317 926 084', Icons.computer_rounded, false),
  ];

  @override
  void dispose() {
    remoteId.dispose();
    super.dispose();
  }

  void previewAction() => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('UI preview only — no remote connection is made.')),
      );

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final screen = selected == 3
            ? settings()
            : selected == 2 && !compact
                ? identity()
                : compact || selected == 1
                    ? directory()
                    : composer();
        final body = ListView(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 24, vertical: compact ? 12 : 18),
            children: [screen]);
        if (!compact) {
          return WorkspaceNavigation(
              brand: 'RustDesk',
              mark: Image.asset('assets/rustdesk-mark.webp',
                  package: 'rustdesk_ui', filterQuality: FilterQuality.medium),
              destinations: const [
                WorkspaceDestination('Connection', Icons.north_east_rounded),
                WorkspaceDestination(
                    'Accessible devices', Icons.devices_rounded),
                WorkspaceDestination('Your Desktop', Icons.laptop_mac_rounded),
              ],
              current: selected,
              onSelect: (i) => setState(() => selected = i),
              settings: 'Settings',
              onSettings: () => setState(() => selected = 3),
              child: body);
        }
        return Column(children: [
          Expanded(child: body),
          if (selected != 3)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => SafeArea(
                            child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    16 +
                                        MediaQuery.viewInsetsOf(context)
                                            .bottom),
                                child: formPanel(onSubmit: () {
                                  Navigator.of(context).pop();
                                  previewAction();
                                })))),
                    icon: const Icon(Icons.north_east_rounded),
                    label: const Text('Connect'))),
          BottomNavigationBar(
              currentIndex: selected == 3 ? 1 : 0,
              onTap: (i) => setState(() => selected = i == 1 ? 3 : 1),
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.devices_outlined), label: 'Connection'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.tune_rounded), label: 'Settings')
              ]),
        ]);
      });

  Widget identity() => WorkspacePanel(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const WorkspaceIcon(icon: Icons.laptop_mac_outlined, size: 36),
          const SizedBox(height: 16),
          Text('Your desktop', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          muted('Share your ID to get support.', size: 12),
          const SizedBox(height: 22),
          muted('YOUR ID', size: 10),
          const SizedBox(height: 7),
          const SelectableText('701 286 493',
              style: TextStyle(
                  fontSize: 21,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w600)),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1)),
          muted('ONE-TIME PASSWORD', size: 10),
          const SizedBox(height: 7),
          const Text('• • • • • •',
              style: TextStyle(fontSize: 20, letterSpacing: 2)),
        ]),
      );

  Widget composer() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Connection',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SessionModePicker(choices: const [
          WorkspaceDestination(
              'Control Remote Desktop', Icons.desktop_windows_outlined),
          WorkspaceDestination('Transfer file', Icons.folder_open_rounded),
          WorkspaceDestination('Terminal', Icons.terminal_rounded),
          WorkspaceDestination('View camera', Icons.videocam_outlined),
        ], selected: mode, onSelect: (value) => setState(() => mode = value)),
        const SizedBox(height: 16),
        formPanel(),
        const SizedBox(height: 24),
        Text('Recent sessions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        for (final device in devices) deviceRow(device),
      ]);

  Widget formPanel({VoidCallback? onSubmit}) {
    void submit() {
      if (form.currentState!.validate()) (onSubmit ?? previewAction)();
    }

    return ConnectionPanel(
        title: 'Remote ID',
        controls: Form(
            key: form,
            child: LayoutBuilder(builder: (context, bounds) {
              final input = TextFormField(
                  controller: remoteId,
                  decoration: const InputDecoration(
                      hintText: 'Enter remote ID',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag_rounded),
                      contentPadding: EdgeInsets.symmetric(vertical: 14)),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a remote ID'
                      : null,
                  onFieldSubmitted: (_) => submit());
              final action = ElevatedButton.icon(
                  style:
                      ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: submit,
                  icon: const Icon(Icons.north_east_rounded, size: 18),
                  label: const Text('Connect'));
              if (bounds.maxWidth >= 330) {
                return Row(children: [
                  Expanded(child: input),
                  const SizedBox(width: 6),
                  action
                ]);
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [input, action]);
            })));
  }

  Widget deviceRow((String, String, IconData, bool) device) {
    final theme = Theme.of(context);
    return Column(children: [
      ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minVerticalPadding: 10,
          leading: WorkspaceIcon(icon: device.$3, size: 38),
          title: Text(device.$1, style: theme.textTheme.titleMedium),
          subtitle: Text(device.$2,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          trailing: Icon(Icons.arrow_outward_rounded,
              size: 18, color: theme.hintColor),
          onTap: previewAction),
      const Divider(height: 1),
    ]);
  }

  Widget directory() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const WorkspaceHeading(title: 'Accessible devices'),
        const SizedBox(height: 20),
        TextField(
          decoration: const InputDecoration(
              hintText: 'Search devices',
              prefixIcon: Icon(Icons.search_rounded)),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 16),
        for (final device in devices.where(
            (device) => device.$1.toLowerCase().contains(query.toLowerCase())))
          deviceRow(device),
        if (devices.every(
            (device) => !device.$1.toLowerCase().contains(query.toLowerCase())))
          Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: muted('No matching devices'))),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: WorkspaceStyle.muted),
          const SizedBox(width: 8),
          Expanded(
              child: muted(
                  'Sample data · This preview does not connect to devices.',
                  size: 11)),
        ]),
      ]);

  Widget settings() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const WorkspaceHeading(
            title: 'Settings',
            trailing: WorkspaceIcon(icon: Icons.tune_rounded)),
        const SizedBox(height: 32),
        Text('Preferences', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        WorkspacePanel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SwitchListTile.adaptive(
                title: const Text('Notifications'),
                subtitle: const Text('Keep up with incoming requests'),
                value: notifications,
                activeColor: WorkspaceStyle.accent,
                onChanged: (value) => setState(() => notifications = value),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile.adaptive(
                title: const Text('Clipboard sharing'),
                subtitle: const Text('Copy and paste between devices'),
                value: clipboard,
                activeColor: WorkspaceStyle.accent,
                onChanged: (value) => setState(() => clipboard = value),
              ),
            ])),
        const SizedBox(height: 24),
        WorkspacePanel(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const WorkspaceIcon(icon: Icons.science_outlined),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('UI preview',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                muted(
                    'These switches demonstrate UI states only. RustDesk preferences and remote sessions are unchanged.'),
              ])),
        ])),
      ]);

  Widget muted(String text, {double size = 13}) => Text(text,
      style: TextStyle(
          color: Theme.of(context).hintColor, fontSize: size, height: 1.5));
}
