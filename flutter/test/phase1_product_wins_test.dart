import 'dart:convert';

import 'package:flutter_hbb/common/local_peer_backup.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/settings_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local peer backup round-trips favorites and aliases without secrets',
      () {
    final rawRecent = jsonEncode([
      {
        'id': '123 456 789',
        'alias': 'Office PC',
        'hostname': 'workstation',
        'username': 'alice',
        'platform': 'Windows',
        'password': 'secret-password',
        'hash': 'secret-hash',
      },
      {
        'id': '987654321',
        'alias': 'Lab Mac',
        'hostname': 'macbook',
        'platform': 'Mac OS',
      },
    ]);

    final bundle = buildLocalPeerBackup(
      recentPeersJson: rawRecent,
      favorites: ['987654321', '555666777'],
      now: DateTime.utc(2026, 11, 27),
    );
    final encoded = bundle.encode();
    expect(encoded, isNot(contains('secret-password')));
    expect(encoded, isNot(contains('secret-hash')));

    final decoded = LocalPeerBackupBundle.decode(encoded);
    expect(decoded.peers.length, 3);
    // Favorites sort first.
    expect(decoded.peers[0].id, '555666777');
    expect(decoded.peers[0].favorite, isTrue);
    expect(decoded.peers[1].id, '987654321');
    expect(decoded.peers[1].alias, 'Lab Mac');
    expect(decoded.peers[1].favorite, isTrue);
    expect(decoded.peers[2].id, '123456789');
    expect(decoded.peers[2].favorite, isFalse);

    final merged = mergeFavoriteIds(['111222333', '987654321'], decoded.peers);
    expect(merged, ['111222333', '987654321', '555666777']);

    expect(
      () => LocalPeerBackupBundle.decode('{"format":"unknown","peers":[]}'),
      throwsFormatException,
    );
  });

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

    final backup = searchDesktopSettings(
      query: '备份',
      availableTabs: available,
      translateLabel: (k) => k,
    );
    expect(backup.matchingTabs, contains(SettingsTabKey.account));

    final audio = searchDesktopSettings(
      query: 'vb-cable',
      availableTabs: available,
      translateLabel: (k) => k,
    );
    expect(audio.matchingTabs, contains(SettingsTabKey.audio));
  });
}
