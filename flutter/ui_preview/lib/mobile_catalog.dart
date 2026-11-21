import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

/// Sample content rendered with production mobile chrome. No native bridge.
class MobileScreensCatalog extends StatefulWidget {
  const MobileScreensCatalog({super.key});

  static const screens = <String, String>{
    'settings': 'Settings',
    'favorites': 'Favorites',
    'address-book': 'Address book',
    'session': 'Remote session',
    'controls': 'Session controls',
    'keyboard': 'Remote keyboard',
    'gestures': 'Gesture guide',
    'files': 'File transfer',
    'chat': 'Chat',
    'dialog': 'Server dialog',
    'shortcuts': 'Keyboard shortcuts',
  };

  @override
  State<MobileScreensCatalog> createState() => _MobileScreensCatalogState();
}

class _MobileScreensCatalogState extends State<MobileScreensCatalog> {
  late String screen = MobileScreensCatalog.screens
          .containsKey(Uri.base.queryParameters['screen'])
      ? Uri.base.queryParameters['screen']!
      : 'settings';
  bool clipboard = true;
  bool hardware = true;
  bool pointer = true;
  bool local = false;
  bool sent = false;
  final message = TextEditingController();

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  void notice() => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sample data only — no device or preference is changed.')));

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: screen,
              icon: const Icon(Icons.unfold_more_rounded, size: 20),
              items: MobileScreensCatalog.screens.entries
                  .map((entry) => DropdownMenuItem(
                      value: entry.key, child: Text(entry.value)))
                  .toList(),
              onChanged: (value) => setState(() => screen = value!),
            ),
          ),
        ),
        Expanded(
            child: screen == 'session'
                ? session()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('MOBILE WORKSPACE · SAMPLE DATA',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.1,
                                  color: Theme.of(context).hintColor)),
                          const SizedBox(height: 16),
                          WorkspaceHeading(
                              title: MobileScreensCatalog.screens[screen]!,
                              subtitle: subtitle,
                              trailing: WorkspaceIcon(icon: screenIcon)),
                          const SizedBox(height: 28),
                          ...content(),
                        ]),
                  )),
      ]);

  String get subtitle => switch (screen) {
        'settings' => 'Make your workspace feel like yours.',
        'favorites' => 'Your go-to devices, one tap away.',
        'address-book' => 'All your devices. Beautifully organized.',
        'controls' => 'Everything you need, within reach.',
        'keyboard' => 'Desktop shortcuts. Made for touch.',
        'gestures' => 'A natural way to work remotely.',
        'files' => 'Your files, on either side.',
        'chat' => 'Stay connected while you work.',
        'dialog' => 'Connect through your own infrastructure.',
        _ => 'A faster way to get things done.',
      };

  IconData get screenIcon => switch (screen) {
        'settings' => Icons.tune_rounded,
        'favorites' => Icons.star_outline_rounded,
        'address-book' => Icons.contacts_outlined,
        'files' => Icons.folder_outlined,
        'chat' => Icons.chat_bubble_outline_rounded,
        'dialog' => Icons.dns_outlined,
        'keyboard' || 'shortcuts' => Icons.keyboard_outlined,
        _ => Icons.touch_app_outlined,
      };

  Widget section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: MobileWorkspaceSection(
            title: title, child: Column(children: children)),
      );

  Widget row(String title, String detail, IconData icon, {Widget? trailing}) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: WorkspaceIcon(icon: icon, size: 38),
        title: Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(detail,
            style: TextStyle(
                fontSize: 11, color: Theme.of(context).hintColor, height: 1.6)),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: notice,
      );

  List<Widget> content() => switch (screen) {
        'settings' => [
            section('ACCOUNT', [
              row('Alex Morgan', 'Personal workspace',
                  Icons.person_outline_rounded)
            ]),
            section('CONNECTION', [
              row('ID / Relay server', 'Use your own server',
                  Icons.dns_outlined),
              const Divider(height: 1, indent: 66),
              row('Display settings', 'Quality, codec and view style',
                  Icons.monitor_outlined),
              const Divider(height: 1, indent: 66),
              row('Keyboard shortcuts', 'Work faster from anywhere',
                  Icons.keyboard_outlined),
            ]),
            section('PREFERENCES', [
              SwitchListTile(
                  title: const Text('Sync clipboard'),
                  subtitle: const Text('Copy between devices'),
                  value: clipboard,
                  onChanged: (value) => setState(() => clipboard = value)),
              const Divider(height: 1, indent: 16),
              SwitchListTile(
                  title: const Text('Hardware codec'),
                  subtitle: const Text('Smooth, efficient streaming'),
                  value: hardware,
                  onChanged: (value) => setState(() => hardware = value)),
            ]),
            section('ABOUT', [
              row('RustDesk', 'Privacy · Version information',
                  Icons.info_outline_rounded)
            ]),
          ],
        'favorites' || 'address-book' => [
            if (screen == 'address-book')
              section('PERSONAL ADDRESS BOOK', [
                row('My devices', '3 devices', Icons.contacts_outlined),
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Wrap(spacing: 8, children: [
                      for (final label in ['All', 'Work', 'Home'])
                        Chip(
                            label: Text(label),
                            backgroundColor: label == 'All'
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(.12)
                                : null,
                            side: BorderSide(
                                color: Theme.of(context).dividerColor))
                    ])),
              ]),
            const TextField(
                decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search devices')),
            const SizedBox(height: 24),
            section('SAVED DEVICES', [
              row('Studio Mac', 'macOS · 842 193 506', Icons.laptop_mac_rounded,
                  trailing: const Icon(Icons.circle,
                      color: Color(0xFF26A77D), size: 8)),
              const Divider(height: 1, indent: 66),
              row('Office workstation', 'Windows · 625 048 319',
                  Icons.desktop_windows_outlined,
                  trailing: const Icon(Icons.circle,
                      color: Color(0xFF26A77D), size: 8)),
              if (screen == 'address-book') ...[
                const Divider(height: 1, indent: 66),
                row('Living room PC', 'Windows · Offline',
                    Icons.computer_outlined,
                    trailing: Icon(Icons.circle,
                        color: Theme.of(context).hintColor, size: 8)),
              ],
            ]),
          ],
        'controls' => [
            section('SESSION', [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 8,
                      children: [
                        for (final entry in [
                          ('Disconnect', Icons.link_off_rounded),
                          ('Screenshot', Icons.screenshot_monitor_outlined),
                          ('Sound', Icons.volume_up_outlined),
                          ('Displays', Icons.monitor_outlined),
                          ('Chat', Icons.chat_bubble_outline_rounded),
                          ('More', Icons.more_horiz_rounded),
                        ])
                          SizedBox(
                              width: 92,
                              child: TextButton(
                                  onPressed: notice,
                                  style: TextButton.styleFrom(
                                      foregroundColor: entry.$1 == 'Disconnect'
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface),
                                  child: Column(children: [
                                    Icon(entry.$2, size: 23),
                                    const SizedBox(height: 10),
                                    Text(entry.$1,
                                        style: const TextStyle(fontSize: 10))
                                  ]))),
                      ]))
            ]),
            section('INPUT MODE', [
              RadioListTile<bool>(
                  title: const Text('Pointer mode'),
                  value: true,
                  groupValue: pointer,
                  onChanged: (value) => setState(() => pointer = value!)),
              RadioListTile<bool>(
                  title: const Text('Touchscreen mode'),
                  value: false,
                  groupValue: pointer,
                  onChanged: (value) => setState(() => pointer = value!)),
            ]),
            section('DISPLAY & CONNECTION', [
              row('Display settings', 'Balanced · Adaptive',
                  Icons.monitor_outlined),
              row('Keyboard', 'Shortcuts and full keyboard',
                  Icons.keyboard_outlined)
            ]),
            Text(
                'SwiftUI sheet design reference; native input is not running here.',
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        'keyboard' => [
            section('REMOTE KEYBOARD', [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    for (final keys in [
                      ['Ctrl', 'Alt', 'Shift', '⌘'],
                      ['Esc', 'Tab', 'Home', 'End'],
                      ['F1', 'F2', 'F3', 'F4'],
                      ['←', '↑', '↓', '→']
                    ])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            for (final key in keys)
                              Expanded(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3),
                                      child: OutlinedButton(
                                          onPressed: notice,
                                          style: OutlinedButton.styleFrom(
                                              padding: EdgeInsets.zero),
                                          child: Text(key,
                                              style: const TextStyle(
                                                  fontSize: 12))))),
                          ])),
                  ]))
            ]),
            section('QUICK ACTIONS', [
              row('Copy', '⌘ C / Ctrl C', Icons.copy_outlined),
              row('Paste', '⌘ V / Ctrl V', Icons.paste_outlined)
            ]),
          ],
        'gestures' => [
            section('POINTER MODE', [
              row('Move pointer', 'Slide one finger', Icons.mouse_outlined),
              row('Left click', 'Tap with one finger',
                  Icons.touch_app_outlined),
              row('Right click', 'Tap with two fingers',
                  Icons.pan_tool_alt_outlined),
              row('Scroll', 'Slide two fingers', Icons.unfold_more_rounded),
            ]),
            section('TOUCHSCREEN MODE', [
              row('Direct touch', 'Tap where you want to click',
                  Icons.ads_click_rounded)
            ])
          ],
        'files' => [
            WorkspacePanel(
                padding: const EdgeInsets.all(4),
                child: Row(children: [
                  for (final entry in [(true, 'Local'), (false, 'Remote')])
                    Expanded(
                        child: TextButton(
                            style: TextButton.styleFrom(
                                backgroundColor: local == entry.$1
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(.12)
                                    : null),
                            onPressed: () => setState(() => local = entry.$1),
                            child: Text(entry.$2))),
                ])),
            const SizedBox(height: 20),
            Text(local ? 'This iPhone / Documents' : 'Studio Mac / Documents',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 16),
            section('FILES', [
              row('Projects', 'Folder · 12 items', Icons.folder_outlined),
              const Divider(height: 1, indent: 66),
              row('Brand assets', 'Folder · 8 items', Icons.folder_outlined),
              const Divider(height: 1, indent: 66),
              row('Proposal.pdf', '2.4 MB · Today, 09:41',
                  Icons.description_outlined),
              const Divider(height: 1, indent: 66),
              row('Meeting notes.txt', '12 KB · Yesterday',
                  Icons.article_outlined)
            ]),
            WorkspacePanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Proposal.pdf',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('Sending to this iPhone · 1.8 / 2.4 MB',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor)),
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(value: .75, minHeight: 4)
                    ])),
          ],
        'chat' => [
            MobileSessionSurface(
                child: Column(children: [
              MobileChatHeader(
                  title: 'Studio Mac',
                  onMinimize: notice,
                  onClose: notice,
                  minimizeLabel: 'Minimize',
                  closeLabel: 'Close'),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text('TODAY · 09:41',
                        style: TextStyle(
                            fontSize: 9, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 24),
                    bubble(
                        'Hi Alex, can you check the display settings?', false),
                    const SizedBox(height: 16),
                    bubble('Of course. Everything looks good now.', true),
                    if (sent) ...[
                      const SizedBox(height: 16),
                      bubble('Thanks for your help!', true)
                    ],
                    const SizedBox(height: 40),
                    TextField(
                        controller: message,
                        decoration: InputDecoration(
                            hintText: 'Write a message',
                            suffixIcon: IconButton(
                                tooltip: 'Send sample message',
                                icon: const Icon(Icons.send_rounded),
                                onPressed: () => setState(() {
                                      sent = true;
                                      message.clear();
                                    })))),
                  ])),
            ]))
          ],
        'dialog' => [
            section('SELF-HOSTED CONNECTION', [
              row('ID / Relay server', 'Set up a trusted connection',
                  Icons.dns_outlined)
            ]),
            ElevatedButton.icon(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => MobileWorkspaceDialog(
                            title: const Text('ID / Relay server'),
                            content: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                      decoration: InputDecoration(
                                          labelText: 'ID server',
                                          hintText: 'id.example.com')),
                                  SizedBox(height: 16),
                                  TextField(
                                      decoration: InputDecoration(
                                          labelText: 'API server',
                                          hintText: 'https://api.example.com')),
                                  SizedBox(height: 16),
                                  TextField(
                                      obscureText: true,
                                      decoration:
                                          InputDecoration(labelText: 'Key')),
                                  SizedBox(height: 8),
                                ]),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    notice();
                                  },
                                  child: const Text('Save')),
                            ])),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Edit server settings')),
          ],
        _ => [
            section('KEYBOARD SHORTCUTS', [
              row('Copy', '⌘ C', Icons.copy_outlined),
              row('Paste', '⌘ V', Icons.paste_outlined),
              row('Select all', '⌘ A', Icons.select_all_rounded),
              row('Switch window', '⌘ Tab', Icons.tab_rounded),
            ]),
            WorkspacePanel(
                padding: const EdgeInsets.all(16),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              'Connect a physical keyboard to record custom shortcuts.',
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: Theme.of(context).hintColor)))
                    ]))
          ],
      };

  Widget bubble(String text, bool own) => Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
          constraints: const BoxConstraints(maxWidth: 238),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: own
                  ? WorkspaceStyle.accent
                  : Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16)),
          child: Text(text,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: own
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface))));

  Widget session() => Container(
      color: const Color(0xFF101725),
      child: Stack(children: [
        Positioned.fill(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.desktop_mac_rounded,
                          size: 54, color: Color(0xFF66758C)),
                      const SizedBox(height: 20),
                      const Text('Studio Mac',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text('REMOTE CANVAS · SAMPLE DATA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF9AA9BF),
                              fontSize: 9,
                              letterSpacing: 1.3)),
                      const SizedBox(height: 32),
                      Container(
                          height: 180,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                              color: const Color(0xFF1A2436),
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFF303E54))),
                          child: Column(children: [
                            const Row(children: [
                              Icon(Icons.circle,
                                  color: Color(0xFFEF6685), size: 7),
                              SizedBox(width: 5),
                              Icon(Icons.circle,
                                  color: Color(0xFFF4BE4F), size: 7),
                              SizedBox(width: 5),
                              Icon(Icons.circle,
                                  color: Color(0xFF4FD1A1), size: 7)
                            ]),
                            const SizedBox(height: 26),
                            for (final width in [1.0, .7, .85])
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: FractionallySizedBox(
                                      widthFactor: width,
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                          height: 8,
                                          decoration: BoxDecoration(
                                              color: const Color(0xFF303E54),
                                              borderRadius:
                                                  BorderRadius.circular(4))))),
                          ])),
                    ]))),
        Positioned(
            left: 16,
            top: 16,
            right: 16,
            child: MobileSessionSurface(
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.circle,
                          color: Color(0xFF26A77D), size: 7),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('Studio Mac',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600))),
                      Text('28 ms',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor)),
                    ])))),
        Positioned(
            right: 16,
            bottom: 20,
            child: MobileSessionSurface(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final entry in [
                ('Pointer', Icons.mouse_outlined),
                ('Keyboard', Icons.keyboard_outlined),
                ('Session controls', Icons.tune_rounded)
              ])
                IconButton(
                    tooltip: entry.$1,
                    onPressed: () => setState(() => screen =
                        entry.$1 == 'Keyboard' ? 'keyboard' : 'controls'),
                    icon: Icon(entry.$2,
                        color: Theme.of(context).colorScheme.primary))
            ]))),
      ]));
}
