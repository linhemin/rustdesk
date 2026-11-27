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
}
