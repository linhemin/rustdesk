import 'package:flutter/material.dart';

import 'package:rustdesk_ui/rustdesk_ui.dart';

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
              toolbarHeight: 56,
              title: const Text('RustDesk / UI preview',
                  style: TextStyle(fontSize: 15)),
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
        return Column(children: [
          Expanded(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                if (!compact) sidebar(),
                Expanded(
                    child: SingleChildScrollView(
                  padding: EdgeInsets.all(compact ? 20 : 36),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: selected == 2 ? settings() : connections(compact),
                  ),
                )),
              ])),
          if (compact)
            BottomNavigationBar(
              currentIndex: selected,
              backgroundColor: Theme.of(context).cardColor,
              type: BottomNavigationBarType.fixed,
              onTap: (value) => setState(() => selected = value),
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.devices_outlined), label: 'Connection'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.star_outline_rounded), label: 'Favorites'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.tune_rounded), label: 'Settings'),
              ],
            ),
        ]);
      });

  Widget sidebar() => WorkspaceSidebar(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            const Row(children: [
              WorkspaceIcon(icon: Icons.swap_horiz_rounded, size: 40),
              SizedBox(width: 12),
              Flexible(
                  child: Text('RustDesk',
                      style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6))),
            ]),
            const SizedBox(height: 40),
            muted('WORKSPACE', size: 10),
            const SizedBox(height: 12),
            navItem(0, 'Connection', Icons.devices_outlined),
            navItem(1, 'Favorites', Icons.star_outline_rounded),
            navItem(2, 'Settings', Icons.tune_rounded),
            const SizedBox(height: 32),
            identity(),
            const Spacer(),
            const Divider(),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.science_outlined,
                  size: 16, color: WorkspaceStyle.muted),
              const SizedBox(width: 8),
              Flexible(child: muted('UI preview · Sample data', size: 11)),
            ]),
            const SizedBox(height: 12),
          ]),
        ),
      );

  Widget navItem(int index, String label, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected == index
              ? WorkspaceStyle.accent.withOpacity(.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(icon,
                size: 21,
                color: selected == index ? WorkspaceStyle.accent : null),
            title: Text(label,
                style: TextStyle(
                    fontWeight:
                        selected == index ? FontWeight.w600 : FontWeight.w400,
                    color: selected == index ? WorkspaceStyle.accent : null)),
            onTap: () => setState(() => selected = index),
          ),
        ),
      );

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

  Widget connections(bool compact) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        WorkspaceHeading(
          title: selected == 1 ? 'Favorites' : 'Your workspace',
          subtitle: 'A little closer. Wherever you are.',
          trailing: const WorkspaceIcon(icon: Icons.devices_rounded),
        ),
        const SizedBox(height: 30),
        WorkspacePanel(
          child: Form(
            key: form,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.north_east_rounded,
                    color: WorkspaceStyle.accent, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text('Connect to a device',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 8),
              muted('Enter a remote ID to start a session.'),
              const SizedBox(height: 22),
              TextFormField(
                controller: remoteId,
                decoration: const InputDecoration(
                    labelText: 'Remote ID',
                    hintText: '000 000 000',
                    prefixIcon: Icon(Icons.tag_rounded)),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a remote ID'
                    : null,
                onFieldSubmitted: (_) {
                  if (form.currentState!.validate()) previewAction();
                },
              ),
              const SizedBox(height: 16),
              Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (form.currentState!.validate()) previewAction();
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Connect'),
                  )),
            ]),
          ),
        ),
        const SizedBox(height: 32),
        Text(selected == 1 ? 'Starred devices' : 'Recent sessions',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        muted('Your familiar devices, one click away.'),
        const SizedBox(height: 20),
        TextField(
          decoration: const InputDecoration(
              hintText: 'Search devices',
              prefixIcon: Icon(Icons.search_rounded)),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 16),
        for (final device in devices.where((device) =>
            device.$1.toLowerCase().contains(query.toLowerCase()) &&
            (selected != 1 || device.$4)))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: WorkspacePanel(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                WorkspaceIcon(icon: device.$3),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(device.$1,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 5),
                      muted(device.$2, size: 12),
                    ])),
                Icon(device.$4 ? Icons.circle : Icons.circle_outlined,
                    size: 8,
                    color: device.$4
                        ? const Color(0xFF16815E)
                        : Theme.of(context).hintColor),
                const SizedBox(width: 8),
                IconButton(
                    tooltip: 'Open ${device.$1}',
                    onPressed: previewAction,
                    icon: const Icon(Icons.arrow_outward_rounded, size: 18)),
              ]),
            ),
          ),
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
        if (compact) ...[const SizedBox(height: 24), identity()],
      ]);

  Widget settings() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const WorkspaceHeading(
            title: 'Settings',
            subtitle: 'Make yourself at home.',
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
                Text('A space to explore',
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
