import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/device_profile.dart';
import 'package:flutter_hbb/common/incoming_history.dart';
import 'package:flutter_hbb/common/local_peer_backup.dart';
import 'package:flutter_hbb/common/relay_probe.dart';
import 'package:flutter_hbb/common/widgets/relay_servers.dart';
import 'package:flutter_hbb/desktop/widgets/command_palette.dart';
import 'package:flutter_hbb/desktop/widgets/session_whiteboard.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/awesun/awesun_flutter_overlay.dart';
import 'package:flutter_hbb/mobile/widgets/macro_shortcut_bar.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeBind extends Fake implements RustdeskImpl {
  @override
  String translate({required String name, required String locale, dynamic hint}) =>
      name;

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) => '';

  @override
  Future<void> setLocalFlutterOption(
      {required String k, required String v, dynamic hint}) async {}
}

void main() {
  setUpAll(() {
    platformFFI.setBindingForTesting(_FakeBind());
  });
  group('Relay probe & network diagnostics', () {
    test('parseHostPort handles IPv4, domain, bracketed IPv6, and invalid', () {
      expect(parseHostPort('relay.example.com', defaultPort: 21117),
          ('relay.example.com', 21117));
      expect(parseHostPort('relay.example.com:21119', defaultPort: 21117),
          ('relay.example.com', 21119));
      expect(parseHostPort('[::1]:21117', defaultPort: 21117), ('::1', 21117));
      expect(parseHostPort('[2001:db8::1]', defaultPort: 21117),
          ('2001:db8::1', 21117));
      expect(parseHostPort('bad:99999', defaultPort: 21117), isNull);
      expect(parseHostPort('', defaultPort: 21117), isNull);
    });

    test('probeTcpEndpoint & runNetworkDiagnostics report latency and timeout',
        () async {
      Future<Duration> connector(String host, int port, Duration timeout) async {
        if (host == 'slow.example.com') {
          throw TimeoutException('timed out');
        }
        return const Duration(milliseconds: 24);
      }

      final ok = await probeTcpEndpoint(
        'relay1.example.com:21117',
        defaultPort: 21117,
        connector: connector,
      );
      expect(ok.reachable, isTrue);
      expect(ok.latencyMs, 24);

      final fail = await probeTcpEndpoint(
        'slow.example.com:21117',
        defaultPort: 21117,
        connector: connector,
      );
      expect(fail.reachable, isFalse);
      expect(fail.error, 'Timeout');

      final checks = await runNetworkDiagnostics(
        idServer: 'id.example.com',
        relayServers: ['relay1.example.com', 'slow.example.com'],
        directOnly: false,
        connector: connector,
      );
      expect(checks.length, 3);
      expect(checks[0].ok, isTrue);
      expect(checks[1].ok, isTrue);
      expect(checks[2].ok, isFalse);
    });

    testWidgets('RelayServersField probes relays and renders latency badge',
        (tester) async {
      final ctrl = TextEditingController(
        text: jsonEncode([
          {'address': 'relay.example.com:21117', 'key': ''},
        ]),
      );
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RelayServersField(
                controller: ctrl,
                probeConnector: (host, port, timeout) async =>
                    const Duration(milliseconds: 18),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test'), findsOneWidget);
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();
      expect(find.text('18 ms'), findsOneWidget);
    });
  });

  group('WebDAV config & HTTP sync client', () {
    test('WebDavSyncConfig resolves directory URL to backup JSON file', () {
      const dirCfg = WebDavSyncConfig(
        endpoint: 'https://dav.example.com/rustdesk/',
        username: 'alice',
        password: 'pw',
      );
      expect(dirCfg.targetUri.toString(),
          'https://dav.example.com/rustdesk/rustdesk-peers-backup.json');

      const fileCfg = WebDavSyncConfig(
        endpoint: 'https://dav.example.com/custom.json',
        username: '',
        password: '',
      );
      expect(fileCfg.targetUri.toString(),
          'https://dav.example.com/custom.json');
    });

    test('WebDAV PUT sends Basic Auth and valid JSON payload', () async {
      String? capturedMethod;
      String? capturedAuth;
      String? capturedBody;
      final mockClient = MockClient((req) async {
        capturedMethod = req.method;
        capturedAuth = req.headers['Authorization'];
        capturedBody = req.body;
        return http.Response('', 201);
      });

      final bundle = buildLocalPeerBackup(
        recentPeersJson: jsonEncode([
          {'id': '123456789', 'alias': 'Work PC', 'password': 'secret'},
        ]),
        favorites: ['123456789'],
      );
      final encoded = bundle.encode();
      final cfg = const WebDavSyncConfig(
        endpoint: 'https://dav.example.com/sync',
        username: 'u',
        password: 'p',
      );

      final resp = await mockClient.put(
        cfg.targetUri,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic ${base64Encode(utf8.encode('u:p'))}',
        },
        body: encoded,
      );
      expect(resp.statusCode, 201);
      expect(capturedMethod, 'PUT');
      expect(capturedAuth, startsWith('Basic '));
      expect(capturedBody, isNot(contains('secret')));
      expect(LocalPeerBackupBundle.decode(capturedBody!).peers.single.id,
          '123456789');
    });
  });

  group('Desktop command palette & whiteboard', () {
    test('filterDesktopCommands matches across title, subtitle, and keywords',
        () {
      final peers = [
        Peer.fromJson({
          'id': '111222333',
          'alias': 'Studio Mac',
          'hostname': 'mac-pro',
          'platform': 'Mac OS',
        }),
      ];
      final items = buildPeerCommandItems(
        peers: peers,
        onConnectPeer: (_, {isFileTransfer = false, isTerminal = false}) {},
      );
      expect(items.length, 3);
      expect(filterDesktopCommands(items, 'studio terminal').single.id,
          'term:111222333');
      expect(filterDesktopCommands(items, '111222333 file').single.id,
          'file:111222333');
    });

    testWidgets('showDesktopCommandPalette filters and runs tapped item',
        (tester) async {
      var ran = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDesktopCommandPalette(
                  context,
                  items: [
                    DesktopCommandItem(
                      id: 'diag',
                      title: 'Network Diagnostics',
                      subtitle: 'Check servers',
                      icon: Icons.monitor_heart_outlined,
                      onRun: () => ran = true,
                    ),
                  ],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Network Diagnostics'), findsOneWidget);
      await tester.tap(find.text('Network Diagnostics'));
      await tester.pumpAndSettle();
      expect(ran, isTrue);
    });

    testWidgets('WhiteboardController draws strokes, laser, and clears',
        (tester) async {
      final ctrl = WhiteboardController();
      addTearDown(ctrl.dispose);

      expect(ctrl.active, isFalse);
      ctrl.toggle();
      expect(ctrl.tool, WhiteboardTool.pen);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: SessionWhiteboardOverlay(controller: ctrl),
            ),
          ),
        ),
      );

      ctrl.startStroke(const Offset(10, 10));
      ctrl.extendStroke(const Offset(50, 50));
      expect(ctrl.strokes.length, 1);
      expect(ctrl.strokes.single.points.length, 2);

      ctrl.setTool(WhiteboardTool.laser);
      ctrl.updateLaser(const Offset(80, 80));
      expect(ctrl.laserPoint, const Offset(80, 80));

      ctrl.clear();
      expect(ctrl.strokes, isEmpty);
      expect(ctrl.laserPoint, isNull);
    });
  });

  group('P3 profiles, incoming history, mobile macro bar & onboarding tour', () {
    test('DeviceConnectionProfile JSON round-trip and defaults', () {
      const def = DeviceConnectionProfile();
      expect(def.isDefault, isTrue);

      const custom = DeviceConnectionProfile(
        defaultMode: 'terminal',
        quality: 'best',
        privacyMode: true,
        enableAudio: false,
        forceRelay: true,
      );
      expect(custom.isDefault, isFalse);
      final parsed = DeviceConnectionProfile.fromJson(custom.toJson());
      expect(parsed.defaultMode, 'terminal');
      expect(parsed.quality, 'best');
      expect(parsed.privacyMode, isTrue);
      expect(parsed.enableAudio, isFalse);
      expect(parsed.forceRelay, isTrue);
    });

    test('parseIncomingHistory decodes valid entries and skips malformed ones',
        () {
      final raw = jsonEncode([
        {
          'peer_id': '888999000',
          'peer_name': 'Alice',
          'session_type': 'remote',
          'timestamp': '2026-11-27T12:00:00Z',
        },
        {'peer_id': ''},
        'invalid',
      ]);
      final list = parseIncomingHistory(raw);
      expect(list.length, 1);
      expect(list.single.peerId, '888999000');
      expect(list.single.peerName, 'Alice');
    });

    testWidgets('MobileMacroBar renders pinned macros and triggers callback',
        (tester) async {
      MobileMacroShortcut? fired;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileMacroBar(
              initialPinnedIds: const ['copy', 'alt_tab'],
              onTrigger: (m) => fired = m,
            ),
          ),
        ),
      );

      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('Alt+Tab'), findsOneWidget);
      await tester.tap(find.text('Alt+Tab'));
      expect(fired?.id, 'alt_tab');
    });

    testWidgets('AwesunFlutterOverlay first-run tour steps through and dismisses',
        (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AwesunFlutterOverlay(
              touchMode: false,
              canInput: true,
              canSwitchMode: true,
              displayLocked: false,
              soundOn: true,
              qualityVisible: false,
              displayCount: 1,
              showFirstRunTour: true,
              onDismissFirstRunTour: () => dismissed = true,
              onMovePointer: (_) {},
              onLeftClick: (_) {},
              onRightClick: (_) {},
              onMiddleClick: (_) {},
              onLeftDragStart: (_) {},
              onLeftDragEnd: () {},
              onScroll: (_, __) {},
              onToggleLock: () {},
              onSelectTouchMode: (_) {},
              onOpenSystemKeyboard: () {},
              onOpenVirtualKeyboard: () {},
              onOpenDisplaySettings: () {},
              onToggleQuality: () {},
              onOpenChat: () {},
              onOpenMore: () {},
              onDisconnect: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('1/3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.textContaining('2/3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.textContaining('3/3'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(dismissed, isTrue);
      expect(find.textContaining('3/3'), findsNothing);
    });
  });
}
