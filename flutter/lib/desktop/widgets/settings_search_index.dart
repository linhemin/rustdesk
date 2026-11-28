import '../../common.dart';
import '../pages/desktop_setting_page.dart';

class DesktopSettingSearchEntry {
  const DesktopSettingSearchEntry({
    required this.tab,
    required this.labelKey,
    this.aliases = const [],
  });

  final SettingsTabKey tab;
  final String labelKey;
  final List<String> aliases;
}

const List<DesktopSettingSearchEntry> kDesktopSettingSearchEntries = [
  // General
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.general,
    labelKey: 'Language',
    aliases: ['lang', '语言'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.general,
    labelKey: 'Start on boot',
    aliases: ['startup', 'autostart', '开机自启'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.general,
    labelKey: 'Enable hardware codec',
    aliases: ['hwcodec', 'gpu', '硬件编解码', '硬解'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.general,
    labelKey: 'Check for software updates on startup',
    aliases: ['update', '更新'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.general,
    labelKey: 'Enable Direct3D render',
    aliases: ['directx', 'd3d', 'render', '渲染'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.general,
    labelKey: 'Enable Wayland',
    aliases: ['wayland', 'linux'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.general,
    labelKey: 'Wake Lock',
    aliases: ['wakelock', 'sleep', '休眠', '唤醒锁'],
  ),
  // Appearance
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.appearance,
    labelKey: 'Theme',
    aliases: ['dark', 'light', '主题', '深色', '浅色'],
  ),
  // Network
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.network,
    labelKey: 'ID/Relay Server',
    aliases: ['relay', 'server', '中继', '服务器', '自建', '公钥', 'key'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.network,
    labelKey: 'Proxy',
    aliases: ['socks5', 'http', '代理'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.network,
    labelKey: 'Direct connections only',
    aliases: ['direct', 'relay', '仅直连', '跳过中继'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.network,
    labelKey: 'Enable LAN discovery',
    aliases: ['discovery', '局域网发现'],
  ),
  // Security
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: 'Enable direct IP access',
    aliases: ['ip', 'lan', '直连', '局域网', 'port', '端口'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: 'Timeout in minutes',
    aliases: ['auto disconnect', 'timeout', '自动断开', '超时'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: 'Password',
    aliases: ['permanent', 'one-time', '密码', '固定密码', '临时密码'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: 'Set PIN',
    aliases: ['pin', 'unlock', '解锁'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: 'Use IP Whitelisting',
    aliases: ['whitelist', '白名单'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: '2FA',
    aliases: ['totp', '两步验证', '双重验证', 'trusted'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: 'Enable file transfer',
    aliases: ['file', 'clipboard', '文件传输', '剪贴板', '权限'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.safety,
    labelKey: 'Enable clipboard',
    aliases: ['clipboard', 'copy', 'paste', '剪贴板'],
  ),
  // Display & quality
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.display,
    labelKey: 'Default Image Quality',
    aliases: ['bitrate', 'fps', 'codec', '画质', '码率', '帧率', '编解码'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.display,
    labelKey: 'Show remote cursor',
    aliases: ['cursor', 'mouse', '鼠标', '光标', '远程鼠标'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.display,
    labelKey: 'Trackpad speed',
    aliases: ['trackpad', 'touchpad', 'scroll', '触控板', '滚动速度'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.display,
    labelKey: 'Privacy mode',
    aliases: ['black screen', '隐私屏', '黑屏'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.display,
    labelKey: 'Virtual display',
    aliases: ['virtual', 'monitor', '虚拟显示器', 'amyuni'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.display,
    labelKey: 'True color (4:4:4)',
    aliases: ['i444', '真彩'],
  ),
  // Audio & recording
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.audio,
    labelKey: 'Audio Input',
    aliases: ['microphone', 'mic', 'speaker', '音频', '麦克风', '扬声器', 'vb-cable', 'virtual'],
  ),
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.audio,
    labelKey: 'Recording',
    aliases: ['video', '录屏', '录制'],
  ),
  // Shortcuts
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.shortcuts,
    labelKey: 'Keyboard shortcuts',
    aliases: ['hotkey', '快捷键', '按键'],
  ),
  // Account
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.account,
    labelKey: 'Account',
    aliases: ['login', '账号', '登录'],
  ),
  // Printer
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.printer,
    labelKey: 'Remote Printer',
    aliases: ['print', '打印机', '打印'],
  ),
  // About
  DesktopSettingSearchEntry(
    tab: SettingsTabKey.about,
    labelKey: 'Version',
    aliases: ['about', 'license', '版本', '关于'],
  ),
];

const _nativeP2pEntries = {
  'Enable UDP hole punching': ['udp', 'hole punching', 'p2p', '打洞'],
  'Enable TCP hole punching': ['tcp', 'hole punching', 'p2p', '打洞'],
  'Enable IPv6 P2P connection': ['ipv6', 'p2p'],
};

/// Returns matching setting tabs and specific item matches for [query].
({Set<SettingsTabKey> matchingTabs, List<DesktopSettingSearchEntry> matches})
    searchDesktopSettings({
  required String query,
  required List<SettingsTabKey> availableTabs,
  bool expandedSettings = true,
  bool includeNativeP2p = true,
  bool canConnect = true,
  String Function(String key)? translateLabel,
}) {
  final tr = translateLabel ?? translate;
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return (matchingTabs: availableTabs.toSet(), matches: const []);
  }
  final available = availableTabs.toSet();
  final matchingTabs = <SettingsTabKey>{};
  final matches = <DesktopSettingSearchEntry>[];
  final p2pTab = expandedSettings && available.contains(SettingsTabKey.network)
      ? SettingsTabKey.network
      : SettingsTabKey.general;
  final entries = [
    ...kDesktopSettingSearchEntries,
    if (canConnect && available.contains(SettingsTabKey.general)) ...[
      if (includeNativeP2p)
        for (final entry in _nativeP2pEntries.entries)
          DesktopSettingSearchEntry(
            tab: p2pTab, labelKey: entry.key, aliases: entry.value),
      DesktopSettingSearchEntry(
        tab: p2pTab,
        labelKey: 'Enable WebRTC P2P connection',
        aliases: const ['webrtc', 'p2p'],
      ),
    ],
  ];

  for (final entry in entries) {
    if (!available.contains(entry.tab)) continue;
    final localized = tr(entry.labelKey).toLowerCase();
    final hit = localized.contains(q) ||
        entry.labelKey.toLowerCase().contains(q) ||
        entry.aliases.any((a) => a.toLowerCase().contains(q));
    if (hit) {
      matchingTabs.add(entry.tab);
      matches.add(entry);
    }
  }
  return (matchingTabs: matchingTabs, matches: matches);
}
