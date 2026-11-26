import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/relay_servers.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'package:flutter_hbb/common.dart' show ServerConfig, setServerConfig;
import 'package:flutter_hbb/common/relay_servers.dart';
import 'package:flutter_test/flutter_test.dart';

class _TranslationBinding extends Fake implements RustdeskImpl {
  String? saved;
  @override
  String mainGetOptionSync({required String key, dynamic hint}) =>
      key == relayServersOption ? '["r.example"]' : '';
  @override
  bool mainIsOptionFixed({required String key, dynamic hint}) => false;
  @override
  Future<void> mainSetOption(
      {required String key, required String value, dynamic hint}) async {
    saved = value;
  }

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  test('explicit empty relay list overrides the legacy relay', () {
    expect(relayServerText('', 'old.example'), 'old.example');
    expect(relayServerText('[]', 'old.example'), isEmpty);
    expect(relayServerText('{bad json', 'old.example'), isEmpty);
    expect(relayServerText('["a.example","b.example"]', ''),
        'a.example\nb.example');
  });

  test(
      'server sharing preserves multiple relays and independent ID-only imports',
      () {
    final saved = ServerConfig.fromOptions({
      'custom-rendezvous-server': 'id.example',
      'relay-server': 'legacy.example',
      'relay-servers': '["a.example","wss://west.example/ws/relay"]',
    });
    final exported = saved.encode();
    final share = jsonDecode(
        utf8.decode(base64Url.decode(exported.split('').reversed.join())));
    expect(share['relay'], 'a.example');
    expect(ServerConfig.decode(exported).relayServer,
        'a.example\nwss://west.example/ws/relay');
    expect(ServerConfig.decode('{"host":"new.id"}').hasRelayServers, false);
    expect(
        ServerConfig.decode('{"host":"id","relays":[]}').hasRelayServers, true);
  });

  test(
      'mixed relay public keys survive saving and QR import without losing pins',
      () {
    final pin = base64Encode(List.generate(32, (index) => index));
    final rows = [
      {'address': 'a.example', 'key': pin},
      'b.example'
    ];
    final saved = ServerConfig.fromOptions(
        {'relay-servers': jsonEncode(rows), 'key': 'legacy-id-token'});
    final encoded = saved.encode();
    final share = jsonDecode(
        utf8.decode(base64Url.decode(encoded.split('').reversed.join())));
    expect(share['relays'], rows);
    expect(share['relay'], 'b.example');
    expect(share['key'], 'legacy-id-token');
    expect(
        jsonDecode(jsonEncode(
            parseRelayServers(ServerConfig.decode(encoded).relayServer))),
        rows);
    expect(
        ServerConfig.decode('{"host":"id","relay":"legacy.example"}')
            .relayServer,
        'legacy.example');
  });

  test(
      'invalid or conflicting relay identity is never exported or replaced by the inherited key',
      () {
    final pin = base64Encode(List.filled(32, 255));
    final secret = base64Encode(List.filled(64, 255));
    final invalid = [
      for (final key in [
        secret,
        '-----BEGIN PRIVATE KEY-----',
        pin.replaceAll('/', '_'),
        pin.substring(0, 43),
        pin.replaceAll('8=', '9=')
      ])
        [
          {'address': 'r.example', 'key': key}
        ],
      [
        {'address': 'r.example', 'key': pin},
        'R.example:21117'
      ],
      [
        {'address': 'r.example', 'privateKey': secret}
      ],
      for (final address in [
        'relay-id.invalid',
        'test.relay-id.invalid.:21117',
        'wss://abc.RELAY-ID.invalid/ws/relay'
      ])
        [address]
    ];
    for (final data in invalid) {
      final serialized = jsonEncode(data);
      expect(relayServerText(serialized, 'old.example'), isEmpty);
      expect(
          () => ServerConfig.decode(jsonEncode({'host': 'id', 'relays': data})),
          throwsFormatException);
      expect(() => ServerConfig(relayServer: serialized).encode(),
          throwsFormatException);
    }
  });

  testWidgets('removing a relay leaves the other relay attached to its own key',
      (tester) async {
    platformFFI.setBindingForTesting(_TranslationBinding());
    final pin = base64Encode(List.generate(32, (i) => 31 - i));
    final controller = TextEditingController(text: 'a.example\nb.example');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RelayServersField(controller: controller)))));
    await tester.tap(find.byType(DropdownButton<bool>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom public key').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, pin);
    await tester.tap(find.byTooltip('Remove a.example'));
    await tester.pump();
    expect(jsonDecode(jsonEncode(parseRelayServers(controller.text))), [
      {'address': 'b.example', 'key': pin}
    ]);
    await tester.enterText(find.byType(TextField).at(1), '');
    expect(() => parseRelayServers(controller.text), throwsFormatException);
    await tester.tap(find.byType(DropdownButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use the ID server public key').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(jsonEncode(parseRelayServers(controller.text))),
        ['b.example']);
    await tester.enterText(
        find.byType(TextField).first, 'b.example\nc.example');
    await tester.pump();
    expect(jsonDecode(jsonEncode(parseRelayServers(controller.text))),
        ['b.example', 'c.example']);
  });

  testWidgets('saving a custom key requires a complete public key',
      (tester) async {
    final binding = _TranslationBinding();
    platformFFI.setBindingForTesting(binding);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => editRelayServers(context),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom public key').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(binding.saved, isNull);
    expect(find.text('Enter a 32-byte Ed25519 public key in standard Base64'),
        findsOneWidget);
    final draft = tester
        .widget<RelayServersField>(find.byType(RelayServersField))
        .controller
        .text;
    expect(await setServerConfig(null, null, ServerConfig(relayServer: draft)),
        isFalse);
    final pin = base64Encode(List.generate(32, (i) => i));
    await tester.enterText(find.byType(TextField).last, pin);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(jsonDecode(binding.saved!), [
      {'address': 'r.example', 'key': pin}
    ]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(relayServerText('[{"address":"old.example","key":""}]', ''),
        'old.example');
    expect(
        () => parseRelayServers(jsonEncode([
              {'address': 'r.example', 'key': '$pin\n'}
            ])),
        throwsFormatException);
  });

  testWidgets(
      'relay editor supports an empty narrow screen, field errors and a fixed full list',
      (tester) async {
    platformFFI.setBindingForTesting(_TranslationBinding());
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 650);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> show({bool readOnly = false}) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: RelayServersField(
                    controller: controller, readOnly: readOnly)))));
    await show();
    expect(find.text('Direct connections only'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Add relay server'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'bad address');
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .decoration!
            .errorText,
        'Invalid relay server address');
    await tester.tap(find.byType(DropdownButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom public key').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .decoration!
            .errorText,
        contains('Ed25519'));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(980, 800);
    controller.text = List.generate(8, (i) => 'r$i.example').join('\n');
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.byWidgetPredicate((widget) => widget is OutlinedButton))
            .onPressed,
        isNull);
    await show(readOnly: true);
    expect(find.text('Managed by your administrator'), findsOneWidget);
    expect(find.byType(DropdownButton<bool>), findsNothing);
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.readOnly),
        isTrue);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('accepts distinct native and websocket endpoints in input order', () {
    expect(
        parseRelayServers(
                ' Example.com  \nexample.COM:21117\n[::1]:21117\n::1\nwss://s.example/ws/relay\nwss://S.EXAMPLE:443/ws/relay\n10.0.0.2:49000')
            .map((e) => e.address),
        [
          'Example.com',
          '[::1]:21117',
          'wss://s.example/ws/relay',
          '10.0.0.2:49000'
        ]);
    expect(parseRelayServers(' \n\n'), isEmpty);
  });

  test('preserves editable policy when a draft has an invalid address', () {
    for (final bad in [
      'bad name',
      's.example:0',
      's.example:65536',
      'http://node/path',
      's.example/path',
      '[bad::addr]',
      'wss://user@s.example/ws/relay',
      'wss://s.example/ws/relay?token=x',
      'wss://s.example/ws/relay#fragment',
      List.filled(256, 'a').join(),
      List.generate(9, (i) => 'r$i.example').join('\n')
    ]) {
      expect(() => parseRelayServers(bad), throwsFormatException, reason: bad);
    }
  });
}
