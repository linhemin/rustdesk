import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/settings_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop settings search finds tabs by Chinese and English item keywords',
      () {
    final available = SettingsTabKey.values;

    final relay = searchDesktopSettings(
      query: '中继',
      availableTabs: available,
      translateLabel: (k) => k,
    );
    expect(relay.matchingTabs, contains(SettingsTabKey.network));

    final cursor = searchDesktopSettings(
      query: '远程鼠标',
      availableTabs: available,
      translateLabel: (k) => k,
    );
    expect(cursor.matchingTabs, contains(SettingsTabKey.display));

    final audio = searchDesktopSettings(
      query: 'vb-cable',
      availableTabs: available,
      translateLabel: (k) => k,
    );
    expect(audio.matchingTabs, contains(SettingsTabKey.audio));
  });

  test('settings search follows the P2P and security controls by platform', () {
    final native = searchDesktopSettings(
      query: 'p2p',
      availableTabs: SettingsTabKey.values,
      translateLabel: (key) => key,
    );
    expect(native.matches.map((entry) => entry.labelKey), unorderedEquals([
      'Enable UDP hole punching',
      'Enable TCP hole punching',
      'Enable IPv6 P2P connection',
      'Enable WebRTC P2P connection',
    ]));
    expect(native.matchingTabs, {SettingsTabKey.network});

    final web = searchDesktopSettings(
      query: 'p2p',
      availableTabs: [SettingsTabKey.general, SettingsTabKey.network],
      expandedSettings: false,
      includeNativeP2p: false,
      translateLabel: (key) => key,
    );
    expect(web.matches.single.labelKey, 'Enable WebRTC P2P connection');
    expect(web.matches.single.tab, SettingsTabKey.general);

    final timeout = searchDesktopSettings(
      query: '自动断开',
      availableTabs: SettingsTabKey.values,
      translateLabel: (key) => key,
    );
    expect(timeout.matches.single.tab, SettingsTabKey.safety);
  });
}
