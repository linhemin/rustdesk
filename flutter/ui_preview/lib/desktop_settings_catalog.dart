import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:rustdesk_ui/desktop_settings.dart';

const desktopSettingsPages = <(String, IconData)>[
  ('General', Icons.settings_outlined),
  ('Security', Icons.enhanced_encryption_outlined),
  ('Network', Icons.link_outlined),
  ('Display', Icons.desktop_windows_outlined),
  ('Account', Icons.person_outline),
  ('Printer', Icons.print_outlined),
  ('About', Icons.info_outline),
  ('Keyboard shortcuts', Icons.keyboard_outlined),
];

const desktopDialogNames = <String>[
  'Login',
  'Verification code',
  'Connection password',
  'Permanent password',
  'Incoming connection',
  'Connection error',
  'Insecure connection',
  'ID/Relay Server',
  'Socks5/Http(s) Proxy',
  'IP Whitelisting',
  'Unlock settings',
  'Confirmation',
  'Custom image quality',
  'Change ID',
  'Temporary password',
  'About RustDesk',
  'Keyboard shortcut',
];

/// Fixtures use production surfaces, but never load a bridge or save options.
class DesktopSettingsCatalog extends StatefulWidget {
  const DesktopSettingsCatalog({super.key});

  @override
  State<DesktopSettingsCatalog> createState() => _DesktopSettingsCatalogState();
}

class _DesktopSettingsCatalogState extends State<DesktopSettingsCatalog> {
  int selected = 0;
  bool dark = false;
  final values = <String, bool>{};
  final choices = <String, String>{};

  @override
  void initState() {
    super.initState();
    final params = Uri.base.queryParameters;
    dark = params['theme'] == 'dark';
    selected = desktopSettingsPages
        .indexWhere((page) => page.$1.toLowerCase() == params['page']);
    if (selected < 0) selected = 0;
    final dialog = int.tryParse(params['dialog'] ?? '');
    if (dialog != null && dialog >= 0 && dialog < desktopDialogNames.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openDialog(dialog));
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: WorkspaceDesktopStyle.apply(
            WorkspaceStyle.apply(dark ? ThemeData.dark() : ThemeData())),
        child: Builder(
            builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: const Text('Desktop settings & dialogs',
                        style: TextStyle(fontSize: 16)),
                    actions: [
                      const Center(
                          child: Text('Sample data · No preferences are saved',
                              style: TextStyle(fontSize: 12))),
                      const SizedBox(width: 16),
                      PopupMenuButton<int>(
                        tooltip: 'Dialog catalog',
                        icon: const Icon(Icons.web_asset_outlined),
                        onSelected: openDialog,
                        itemBuilder: (_) => List.generate(
                            desktopDialogNames.length,
                            (index) => PopupMenuItem(
                                value: index,
                                child: Text(desktopDialogNames[index]))),
                      ),
                      IconButton(
                          tooltip:
                              dark ? 'Light appearance' : 'Dark appearance',
                          onPressed: () => setState(() => dark = !dark),
                          icon: Icon(dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined)),
                      const SizedBox(width: 12),
                    ],
                  ),
                  body: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        WorkspaceSidebar(
                            width: 232,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          24, 28, 24, 28),
                                      child: Text('Settings',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge)),
                                  Expanded(
                                      child: ListView(
                                          children: List.generate(
                                              desktopSettingsPages.length,
                                              (index) =>
                                                  WorkspaceSettingsNavItem(
                                                    label: desktopSettingsPages[
                                                            index]
                                                        .$1,
                                                    icon: desktopSettingsPages[
                                                            index]
                                                        .$2,
                                                    selected: selected == index,
                                                    onTap: () => setState(
                                                        () => selected = index),
                                                  )))),
                                  Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                          'UI catalog\nProduction surfaces · Sample content',
                                          style: TextStyle(
                                              fontSize: 11,
                                              height: 1.6,
                                              color: Theme.of(context)
                                                  .hintColor))),
                                ])),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              WorkspaceSettingsHeader(
                                  title: desktopSettingsPages[selected].$1,
                                  icon: desktopSettingsPages[selected].$2),
                              Expanded(
                                  child: ListView(
                                      key: ValueKey(selected),
                                      children: content(context))),
                            ])),
                      ]),
                )),
      );

  Widget section(String title, List<Widget> children) =>
      WorkspaceSettingsSection(title: title, children: children);

  Widget toggle(String title, {String? subtitle, bool initial = true}) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: values[title] ?? initial,
        onChanged: (value) => setState(() => values[title] = value),
      );

  Widget choice(String title, List<String> options) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(title)),
          DropdownButton<String>(
            value: choices[title] ?? options.first,
            underline: const SizedBox.shrink(),
            items: options
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) => setState(() => choices[title] = value!),
          ),
        ]),
      );

  Widget action(String label, int dialog, IconData icon) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: WorkspaceIcon(icon: icon, size: 36),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () => openDialog(dialog),
      );

  List<Widget> content(BuildContext context) {
    switch (selected) {
      case 0:
        return [
          section('Service', [
            toggle('Enable service',
                subtitle: 'Allow incoming connections to this device')
          ]),
          section('Theme', [
            choice('Appearance', ['Follow system', 'Light', 'Dark'])
          ]),
          section('Language', [
            choice('Language', ['Default', 'English', '简体中文'])
          ]),
          section('Hardware Codec', [toggle('Enable hardware codec')]),
          section('Audio Input Device', [
            choice('Input device', ['System default', 'Microphone'])
          ]),
          section('Recording', [
            toggle('Automatically record incoming sessions', initial: false),
            choice('Recording directory', ['~/Movies/RustDesk'])
          ]),
          section('Other', [
            toggle('Start RustDesk on boot'),
            toggle('Enable notifications')
          ]),
          section('Keyboard shortcuts', [
            choice('Shortcut preset', ['Default', 'Custom'])
          ]),
        ];
      case 1:
        return [
          section('Permissions', [
            toggle('Enable keyboard/mouse'),
            toggle('Enable clipboard'),
            toggle('Enable file transfer'),
            toggle('Enable remote restart', initial: false)
          ]),
          section('Password', [
            choice('Approve mode', ['Password and click', 'Password', 'Click']),
            action('Set permanent password', 3, Icons.key_outlined)
          ]),
          section('2FA', [
            action('Enable two-factor authentication', 1,
                Icons.verified_user_outlined)
          ]),
          section('ID', [action('Change ID', 13, Icons.badge_outlined)]),
          section('Security', [
            action('Use IP Whitelisting', 9, Icons.shield_outlined),
            action('Unlock settings', 10, Icons.lock_open_outlined)
          ]),
        ];
      case 2:
        return [
          section('Network', [
            action('ID/Relay Server', 7, Icons.dns_outlined),
            const Divider(height: 24),
            action('Socks5/Http(s) Proxy', 8, Icons.public_outlined),
            const Divider(height: 24),
            toggle('Always connect via relay', initial: false),
            toggle('Enable WebSocket', initial: false),
            toggle('Disable UDP', initial: false),
          ]),
        ];
      case 3:
        return [
          section('Default View Style', [
            choice('Scale', ['Scale adaptive', 'Scale original'])
          ]),
          section('Default Scroll Style', [
            choice('Scrolling', ['Auto', 'Scrollbar', 'Edge'])
          ]),
          section('Default Image Quality', [
            choice('Quality',
                ['Balanced', 'Best image quality', 'Optimize reaction time']),
            action('Custom image quality', 12, Icons.tune_rounded)
          ]),
          section('Default Codec', [
            choice('Codec', ['Auto', 'VP8', 'VP9', 'AV1'])
          ]),
          section('Other Default Options', [
            toggle('Show remote cursor'),
            toggle('Enable audio'),
            toggle('Show quality monitor', initial: false)
          ]),
        ];
      case 4:
        return [
          section('Account', [
            const Align(
                alignment: AlignmentDirectional.centerStart,
                child: WorkspaceIcon(
                    icon: Icons.person_outline_rounded, size: 56)),
            const SizedBox(height: 20),
            Text('Login', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Sample signed-out account',
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 24),
            Align(
                alignment: AlignmentDirectional.centerStart,
                child: ElevatedButton(
                    onPressed: () => openDialog(0),
                    child: const Text('Login'))),
          ])
        ];
      case 5:
        return [
          section('Outgoing Print Jobs', [
            toggle('Enable remote printing'),
            choice('Printer driver', ['Installed'])
          ]),
          section('Incoming Print Jobs', [
            choice('Print action', [
              'Use the default printer',
              'Dismiss',
              'Use the selected printer'
            ]),
            choice('Printer', ['Office printer']),
            toggle('Automatically print incoming jobs', initial: false)
          ]),
        ];
      case 6:
        return [
          section('About RustDesk', [
            Row(children: [
              const WorkspaceIcon(icon: Icons.swap_horiz_rounded, size: 56),
              const SizedBox(width: 16),
              Text('RustDesk', style: Theme.of(context).textTheme.headlineSmall)
            ]),
            const SizedBox(height: 24),
            const SelectableText(
                'Version: 1.5.3\n\nBuild Date: Sample build\n\nFingerprint: Sample fingerprint\n\nID: 842 193 506'),
            const SizedBox(height: 16),
            TextButton(
                onPressed: () {}, child: const Text('Privacy Statement')),
            TextButton(onPressed: () {}, child: const Text('Website')),
            const SizedBox(height: 16),
            Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: WorkspaceStyle.accent.withOpacity(.10),
                    borderRadius: BorderRadius.circular(12)),
                child: const Text(
                    'RustDesk\nOpen-source remote desktop software',
                    style: TextStyle(height: 1.7))),
          ])
        ];
      default:
        return [
          section('Keyboard shortcuts', [
            Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                    onPressed: () => openDialog(11),
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to defaults'))),
            const SizedBox(height: 20),
            for (final label in ['General', 'View', 'Keyboard', 'Mouse']) ...[
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const Divider(height: 24),
              action(label == 'General' ? 'Toggle toolbar' : 'Edit shortcut',
                  16, Icons.keyboard_outlined),
              const SizedBox(height: 16),
            ],
          ])
        ];
    }
  }

  void openDialog(int index) {
    // The route is above the local Theme, so explicitly carry its appearance.
    final theme = WorkspaceDesktopStyle.apply(
        WorkspaceStyle.apply(dark ? ThemeData.dark() : ThemeData()));
    showDialog<void>(
        context: context,
        builder: (context) =>
            Theme(data: theme, child: CatalogDialog(index: index)));
  }
}

class CatalogDialog extends StatefulWidget {
  const CatalogDialog({super.key, required this.index});
  final int index;
  @override
  State<CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<CatalogDialog> {
  final form = GlobalKey<FormState>();
  bool remember = true;
  double quality = 75;

  Widget field(String label, {bool secret = false, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
            obscureText: secret,
            decoration: InputDecoration(labelText: label, hintText: hint),
            validator: (value) => value == null || value.trim().isEmpty
                ? '$label is required'
                : null),
      );

  void submit() {
    if (form.currentState?.validate() ?? true) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('UI preview only — no settings or credentials are saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.index;
    final title = desktopDialogNames[i];
    final buttons = [
      'Login',
      'Verify',
      'OK',
      'OK',
      'Accept',
      'Retry',
      'Disconnect',
      'OK',
      'OK',
      'OK',
      'Unlock',
      'OK',
      'OK',
      'OK',
      'OK',
      'Close',
      'OK'
    ];
    final body = <Widget>[];
    switch (i) {
      case 0:
        body.addAll([
          field('Username'),
          field('Password', secret: true),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember me'),
              value: remember,
              onChanged: (value) => setState(() => remember = value!))
        ]);
        break;
      case 1:
        body.addAll([
          const Text('Enter the verification code from your authenticator.'),
          const SizedBox(height: 20),
          field('Verification code')
        ]);
        break;
      case 2:
        body.addAll([
          const Text('Enter the password for the remote device.'),
          const SizedBox(height: 20),
          field('Password', secret: true)
        ]);
        break;
      case 3:
        body.addAll([
          field('Password', secret: true),
          field('Confirm password', secret: true)
        ]);
        break;
      case 4:
        body.addAll([
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: WorkspaceIcon(icon: Icons.laptop_mac_rounded),
              title: Text('Studio Mac'),
              subtitle: Text('842 193 506 · Sample device')),
          const SizedBox(height: 16),
          const Text('Requesting access to your desktop.'),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: remember,
              title: const Text('Enable keyboard/mouse'),
              onChanged: (value) => setState(() => remember = value!)),
        ]);
        break;
      case 5:
        body.addAll([
          const WorkspaceIcon(icon: Icons.wifi_off_rounded),
          const SizedBox(height: 20),
          const Text('Remote desktop is offline. Try connecting again later.')
        ]);
        break;
      case 6:
        body.addAll([
          const WorkspaceIcon(icon: Icons.shield_outlined),
          const SizedBox(height: 20),
          const Text(
              'The remote identity could not be verified. Only continue if you trust this device.')
        ]);
        break;
      case 7:
        body.addAll([
          field('ID Server'),
          field('Relay Server'),
          field('API Server'),
          field('Key')
        ]);
        break;
      case 8:
        body.addAll([
          field('Proxy', hint: 'proxy.example.com:1080'),
          field('Username'),
          field('Password', secret: true)
        ]);
        break;
      case 9:
        body.add(field('IP Whitelisting', hint: '192.168.1.0/24'));
        break;
      case 10:
        body.add(field('PIN', secret: true));
        break;
      case 11:
        body.add(const Text('Are you sure you want to log out?'));
        break;
      case 12:
        body.addAll([
          Text('Bitrate: ${quality.round()}%'),
          Slider(
              value: quality,
              min: 10,
              max: 100,
              onChanged: (value) => setState(() => quality = value)),
          const Text('FPS: 30')
        ]);
        break;
      case 13:
        body.add(field('ID'));
        break;
      case 14:
        body.add(DropdownButtonFormField<String>(
            value: '6',
            decoration:
                const InputDecoration(labelText: 'Temporary password length'),
            items: ['6', '8', '10']
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (_) {}));
        break;
      case 15:
        body.addAll([
          const WorkspaceIcon(icon: Icons.swap_horiz_rounded, size: 56),
          const SizedBox(height: 20),
          const Text('RustDesk 1.5.3\nOpen-source remote desktop software')
        ]);
        break;
      case 16:
        body.addAll([
          const Text('Press the shortcut you want to use.'),
          const SizedBox(height: 24),
          Chip(
              label: const Text('Ctrl + Shift + T'),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor),
        ]);
        break;
    }
    return WorkspaceDesktopDialog(
      title: Text(title),
      content: SizedBox(
          width: 400,
          child: Form(
              key: form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: body))),
      actions: [
        if (i != 15)
          OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(i == 4 ? 'Dismiss' : 'Cancel')),
        if (i == 6)
          OutlinedButton(onPressed: submit, child: const Text('Continue')),
        ElevatedButton(onPressed: submit, child: Text(buttons[i])),
      ],
    );
  }
}
