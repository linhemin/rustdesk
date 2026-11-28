import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/brand_links.dart';
import 'package:flutter_hbb/common/incoming_history.dart';
import 'package:flutter_hbb/common/widgets/network_tools_dialogs.dart';
import 'package:flutter_hbb/common/widgets/workspace.dart';
import 'package:flutter_hbb/desktop/widgets/command_palette.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart' show changeIdDialog;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../../native/apple_workspace_navigation.dart';
import '../incoming_connection_link.dart';
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();
  int _destination = 0;
  List<({int windowId, String peerId})> _activeRemoteSessions = const [];
  List<IncomingVisitorRecord> _incomingVisitors = const [];

  Future<void> _refreshIncomingVisitors() async {
    final visitors = await loadIncomingHistory();
    if (mounted) setState(() => _incomingVisitors = visitors);
  }

  Future<void> _refreshActiveRemoteSessions() async {
    final sessions = await rustDeskWinManager.getRemoteSessions();
    if (mounted) setState(() => _activeRemoteSessions = sessions);
  }

  bool _commandPaletteOpen = false;
  late final HardwareKeyboard _hardwareKeyboard = HardwareKeyboard.instance;

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted || _commandPaletteOpen || !usesWorkspaceStyle || bind.isIncomingOnly()) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final primaryModifier = isMacOS
        ? _hardwareKeyboard.isMetaPressed && !_hardwareKeyboard.isControlPressed
        : _hardwareKeyboard.isControlPressed && !_hardwareKeyboard.isMetaPressed;
    if (primaryModifier &&
        !_hardwareKeyboard.isAltPressed &&
        !_hardwareKeyboard.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      _openCommandPalette(context);
      return true;
    }
    return false;
  }

  Future<void> _openCommandPalette(BuildContext context) async {
    if (_commandPaletteOpen) return;
    _commandPaletteOpen = true;
    try {
      final peers = <Peer>[];
    try {
      final raw = await bind.mainLoadRecentPeersForAb(filter: '');
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            peers.add(Peer.fromJson(item));
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    final items = <DesktopCommandItem>[
      ...buildPeerCommandItems(
        peers: peers,
        onConnectPeer: (peer, {isFileTransfer = false, isTerminal = false}) {
          connect(
            context,
            peer.id,
            isFileTransfer: isFileTransfer,
            isTerminal: isTerminal,
          );
        },
      ),
      if (!bind.isOutgoingOnly())
        DesktopCommandItem(
          id: 'nav:desktop',
          title: translate('Your Desktop'),
          subtitle: translate('ID'),
          icon: Icons.laptop_mac_rounded,
          onRun: () => setState(() => _destination = 1),
        ),
      if (!bind.isDisableSettings())
        DesktopCommandItem(
          id: 'nav:settings',
          title: translate('Settings'),
          subtitle: translate('Settings'),
          icon: Icons.settings_outlined,
          onRun: DesktopTabPage.onAddSetting,
        ),
      DesktopCommandItem(
        id: 'tool:diagnostics',
        title: translate('Diagnostics'),
        subtitle: translate('Network'),
        icon: Icons.monitor_heart_outlined,
        onRun: () => showNetworkDiagnosticsDialog(context),
      ),
      DesktopCommandItem(
        id: 'tool:qr',
        title: translate('Export Server Config'),
        subtitle: translate('ID/Relay Server'),
        icon: Icons.qr_code_2_rounded,
        onRun: () => showServerConfigQrDialog(context),
      ),
    ];
      await showDesktopCommandPalette(
        context,
        items: items,
        onConnectRawId: (id) => connect(context, id),
      );
    } finally {
      _commandPaletteOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    if (usesWorkspaceStyle && !isIncomingOnly) {
      final incoming = !bind.isOutgoingOnly();
      final destinations = [
        WorkspaceDestination(
            translate('Home and devices'), Icons.home_outlined),
        if (incoming)
          WorkspaceDestination(
              translate('Your Desktop'), Icons.laptop_mac_rounded),
        WorkspaceDestination(
            translate('Remote sessions'), Icons.desktop_windows_outlined),
        WorkspaceDestination(
            translate('Transfer file'), Icons.folder_open_outlined),
        WorkspaceDestination(translate('Terminal'), Icons.terminal_rounded),
      ];
      final current = _destination < destinations.length ? _destination : 0;
      final incomingIndex = incoming ? 1 : -1;
      final sessionsIndex = incoming ? 2 : 1;
      final requestedMode = current == sessionsIndex
          ? 0
          : current == sessionsIndex + 1
              ? 1
              : current == sessionsIndex + 2
                  ? 2
                  : null;
      void select(int index) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _destination = index);
        if (index == sessionsIndex) {
          _refreshActiveRemoteSessions();
        } else if (index == incomingIndex) {
          _refreshIncomingVisitors();
        }
      }

      final content = Column(children: [
        if (bind.isCustomClient())
          Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [loadLogo(), loadPowered(context)]),
        if (incoming) buildPresetPasswordWarning(),
        if (current == sessionsIndex)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: WorkspacePanel(
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.desktop_windows_outlined,
                      size: 18, color: WorkspaceStyle.success(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${translate('Active sessions')} (${_activeRemoteSessions.length})',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        for (final session in _activeRemoteSessions)
                          ActionChip(
                            label: Text(session.peerId),
                            avatar: Icon(Icons.circle,
                                size: 8,
                                color: WorkspaceStyle.success(context)),
                            onPressed: () async {
                              final selected =
                                  await rustDeskWinManager.activateRemoteSession(
                                      session.windowId, session.peerId);
                              if (!selected && mounted) {
                                await _refreshActiveRemoteSessions();
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: translate('Refresh'),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    onPressed: _refreshActiveRemoteSessions,
                  ),
                ],
              ),
            ),
          ),
        Expanded(
            child: IndexedStack(
                index: current == incomingIndex ? 1 : 0,
                children: [
              ConnectionPage(
                  requestedMode: requestedMode,
                  workspaceTitle: destinations[current].label,
                  notices: current == 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              if (!incoming)
                                Text(translate('outgoing_only_desk_tip'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              Obx(() =>
                                  buildHelpCards(stateGlobal.updateUrl.value)),
                            ])
                      : null),
              if (incoming)
                _identityWorkspace(context, current == incomingIndex),
            ])),
      ]);
      return CallbackShortcuts(
          bindings: {
            SingleActivator(
              LogicalKeyboardKey.keyK,
              meta: isMacOS,
              control: !isMacOS,
            ): () => _openCommandPalette(context),
          },
          child: Focus(
              autofocus: false,
              child: _buildBlock(
                  child: WorkspaceNavigation(
                brand: bind.mainGetAppNameSync(),
                mark: bind.mainGetAppNameSync() == 'RustDesk'
                    ? ExcludeSemantics(
                        child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('R',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14))))
                    : loadIcon(28),
                destinations: destinations,
                current: current,
                onSelect: select,
                identity: incoming
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _localIdentitySummary(context),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _openCommandPalette(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              alignment: AlignmentDirectional.centerStart,
                            ),
                            icon: const Icon(Icons.search_rounded, size: 15),
                            label: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    translate('Search'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  isMacOS ? '⌘K' : 'Ctrl+K',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : null,
                footer: incoming ? const OnlineStatusWidget(compact: true) : null,
                nativeNavigation: isMacOS
                    ? LayoutBuilder(
                        builder: (_, bounds) => AppleWorkspaceNavigation(
                              labels: [
                                for (final item in destinations) item.label
                              ],
                              symbols: [
                                'house',
                                if (incoming) 'laptopcomputer',
                                'display.2',
                                'folder',
                                'terminal',
                              ],
                              selected: current,
                              compact: bounds.maxWidth < 200,
                              navigationOnly: true,
                              onSelect: select,
                            ))
                    : null,
                settings: translate('Settings'),
                onSettings: bind.isDisableSettings()
                    ? null
                    : DesktopTabPage.onAddSetting,
                child: content,
              ))));
    }
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget _localIdentitySummary(BuildContext context) {
    final theme = Theme.of(context);
    return WorkspacePanel(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(translate('ID'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall)),
          Obx(() {
            final ready = !svcStopped.value &&
                stateGlobal.svcStatus.value == SvcStatus.ready;
            return Text(translate(ready ? 'Ready' : 'Status'),
                style: TextStyle(
                    fontSize: 10,
                    color: ready
                        ? WorkspaceStyle.success(context)
                        : theme.hintColor));
          }),
        ]),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: gFFI.serverModel.serverId,
          builder: (_, value, __) => Row(children: [
            Expanded(
                child: SelectableText(value.text,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        fontFeatures: [FontFeature.tabularFigures()]))),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              tooltip: MaterialLocalizations.of(context).copyButtonLabel,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed:
                  value.text.isEmpty ? null : () => _copyLocalId(value.text),
            )
          ]),
        ),
      ]),
    );
  }

  Future<void> _copyLocalId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    showToast(translate('Copied'));
  }

  Widget _identityWorkspace(BuildContext context, bool visible) {
    final theme = Theme.of(context);
    final model = gFFI.serverModel;
    return ListenableBuilder(
        listenable: model,
        builder: (context, _) =>
            ListView(padding: const EdgeInsets.all(24), children: [
              Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(translate('Your Desktop'),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Obx(() => Chip(
                          avatar: Icon(Icons.circle,
                              size: 8,
                              color: !svcStopped.value &&
                                      stateGlobal.svcStatus.value ==
                                          SvcStatus.ready
                                  ? WorkspaceStyle.green
                                  : theme.hintColor),
                          label: Text(
                              translate(svcStopped.value
                                  ? 'Service is not running'
                                  : stateGlobal.svcStatus.value ==
                                          SvcStatus.ready
                                      ? 'Service is running'
                                      : stateGlobal.svcStatus.value ==
                                              SvcStatus.connecting
                                          ? 'connecting_status'
                                          : 'not_ready_status'),
                              style: const TextStyle(fontSize: 12)),
                        )),
                  ]),
              const SizedBox(height: 6),
              Text(translate('desk_tip'),
                  style: TextStyle(color: theme.hintColor)),
              const SizedBox(height: 18),
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: LayoutBuilder(builder: (context, bounds) {
                        final width = bounds.maxWidth < 600
                            ? bounds.maxWidth
                            : (bounds.maxWidth - 14) / 2;
                        return Wrap(spacing: 14, runSpacing: 14, children: [
                          SizedBox(
                              width: width,
                              child: WorkspacePanel(
                                  radius: 12,
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(translate('ID'),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                    color: WorkspaceStyle
                                                        .tertiaryInk(context))),
                                        const SizedBox(height: 12),
                                        ValueListenableBuilder<
                                                TextEditingValue>(
                                            valueListenable: model.serverId,
                                            builder: (_, value, __) =>
                                                Row(children: [
                                                  Expanded(
                                                      child: SelectableText(
                                                          value.text,
                                                          style: theme.textTheme
                                                              .headlineMedium
                                                              ?.copyWith(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  letterSpacing:
                                                                      .5))),
                                                  IconButton(
                                                      tooltip:
                                                          MaterialLocalizations
                                                                  .of(context)
                                                              .copyButtonLabel,
                                                      icon: const Icon(
                                                          Icons.copy_rounded),
                                                      onPressed: value
                                                              .text.isEmpty
                                                          ? null
                                                          : () => _copyLocalId(
                                                              value.text)),
                                                ])),
                                        const SizedBox(height: 12),
                                        ValueListenableBuilder<
                                                TextEditingValue>(
                                            valueListenable: model.serverId,
                                            builder:
                                                (context, value, _) => Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          OutlinedButton.icon(
                                                            icon: const Icon(
                                                                Icons
                                                                    .link_rounded,
                                                                size: 16),
                                                            label: Text(translate(
                                                                'Copy invitation')),
                                                            onPressed: value
                                                                        .text
                                                                        .trim()
                                                                        .isEmpty ||
                                                                    value.text ==
                                                                        translate(
                                                                            'Generating ...')
                                                                ? null
                                                                : () async =>
                                                                    _copyLocalId(
                                                                        incomingConnectionLink(
                                                                      windowsLicense: isWindows
                                                                          ? await bind.mainGetLicense()
                                                                          : '',
                                                                      uriPrefix:
                                                                          bind.mainUriPrefixSync(),
                                                                      id: value
                                                                          .text
                                                                          .replaceAll(
                                                                              ' ',
                                                                              ''),
                                                                      server: bind
                                                                          .mainGetOptionSync(
                                                                              key: 'custom-rendezvous-server'),
                                                                      key: bind.mainGetOptionSync(
                                                                          key:
                                                                              'key'),
                                                                    )),
                                                          ),
                                                          if (!isChangeIdDisabled() &&
                                                              !bind
                                                                  .isDisableSettings() &&
                                                              bind.mainGetBuildinOption(
                                                                      key:
                                                                          kOptionHideSecuritySetting) !=
                                                                  'Y')
                                                            TextButton(
                                                              onPressed:
                                                                  model.connectStatus <=
                                                                          0
                                                                      ? null
                                                                      : () {
                                                                          if (bind
                                                                              .mainIsInstalled()) {
                                                                            DesktopSettingPage.switch2page(SettingsTabKey.safety);
                                                                          } else {
                                                                            changeIdDialog();
                                                                          }
                                                                        },
                                                              child: Text(translate(
                                                                  'Change ID')),
                                                            ),
                                                        ])),
                                      ]))),
                          SizedBox(
                              width: width,
                              child: WorkspacePanel(
                                radius: 12,
                                padding: const EdgeInsets.all(4),
                                child: buildPasswordBoard(context),
                              )),
                        ]);
                      }))),
              if (!bind.isDisableSettings() &&
                  bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) !=
                      'Y')
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 720),
                    margin: const EdgeInsets.only(top: 16),
                    child: WorkspacePanel(
                      radius: 12,
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(translate('Security'),
                                style: theme.textTheme.labelLarge),
                            const SizedBox(height: 6),
                            for (final mode in {
                              'password': 'Accept sessions via password',
                              'click': 'Accept sessions via click',
                              defaultOptionApproveMode:
                                  'Accept sessions via both',
                            }.entries)
                              RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                title: Text(translate(mode.value),
                                    style: theme.textTheme.bodyMedium),
                                value: mode.key,
                                groupValue: const ['password', 'click']
                                        .contains(model.approveMode)
                                    ? model.approveMode
                                    : defaultOptionApproveMode,
                                onChanged: bind.mainIsInstalled() ||
                                        isOptionFixed(kOptionApproveMode)
                                    ? null
                                    : (value) => model.setApproveMode(value!),
                              ),
                          ],
                        )),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          child: Text(translate('Settings')),
                        ),
                      ]),
                    ),
                  ),
                ),
              if (isMacOS) _incomingMacPermissions(context),
              _incomingHostReadinessAndVisitors(context),
              if (visible)
                Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),
            ]));
  }

  Widget _incomingHostReadinessAndVisitors(BuildContext context) {
    final theme = Theme.of(context);
    final visitors = _incomingVisitors;
    final readySvc =
        !svcStopped.value && stateGlobal.svcStatus.value == SvcStatus.ready;
    final hasPassword = gFFI.serverModel.serverPasswd.text.trim().isNotEmpty;
    final macPermsOk = !isMacOS ||
        (bind.mainIsCanScreenRecording(prompt: false) &&
            bind.mainIsProcessTrusted(prompt: false));
    Widget checkRow(String label, bool ok) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.info_outline_rounded,
                size: 16,
                color: ok
                    ? WorkspaceStyle.success(context)
                    : WorkspaceStyle.warning(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkspacePanel(
              radius: 12,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate('Status'),
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  checkRow(translate('Service is running'), readySvc),
                  checkRow(translate('Password'), hasPassword),
                  checkRow(translate('Permissions'), macPermsOk),
                ],
              ),
            ),
            const SizedBox(height: 14),
            WorkspacePanel(
              radius: 12,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          translate('Recent Sessions'),
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: translate('Refresh'),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        onPressed: _refreshIncomingVisitors,
                      ),
                      if (visitors.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            if (await clearIncomingHistory()) {
                              await _refreshIncomingVisitors();
                            } else if (mounted) {
                              showToast(translate('Failed'));
                            }
                          },
                          child: Text(translate('Clear')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (visitors.isEmpty)
                    Text(
                      translate('Empty'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor),
                    )
                  else
                    for (final rec in visitors.take(8))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.history_rounded,
                                size: 16, color: theme.hintColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                rec.peerName.isNotEmpty
                                    ? '${rec.peerName} (${rec.peerId})'
                                    : rec.peerId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              rec.timestampIso.length >= 16
                                  ? rec.timestampIso
                                      .substring(0, 16)
                                      .replaceFirst('T', ' ')
                                  : rec.timestampIso,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incomingMacPermissions(BuildContext context) {
    Widget row(String label, bool granted, VoidCallback configure) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
              granted ? Icons.check_circle_outline : Icons.warning_amber,
              color: granted ? WorkspaceStyle.green : WorkspaceStyle.amber),
          title: Text(translate(label)),
          trailing: granted
              ? Text(translate('Permission granted'),
                  style: Theme.of(context).textTheme.bodySmall)
              : TextButton(
                  onPressed: configure, child: Text(translate('Configure'))),
        );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(top: 16),
        child: WorkspacePanel(
          radius: 12,
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(translate('Permissions'),
                style: Theme.of(context).textTheme.labelLarge),
            row('Screen recording',
                bind.mainIsCanScreenRecording(prompt: false), () {
              bind.mainIsCanScreenRecording(prompt: true);
              launchUrl(Uri.parse(
                  'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));
              watchIsCanScreenRecording = true;
            }),
            row('Accessibility', bind.mainIsProcessTrusted(prompt: false), () {
              bind.mainIsProcessTrusted(prompt: true);
              watchIsProcessTrust = true;
            }),
            row('Input monitoring',
                bind.mainIsCanInputMonitoring(prompt: false), () {
              bind.mainIsCanInputMonitoring(prompt: true);
              watchIsInputMonitoring = true;
            }),
          ]),
        ),
      ),
    );
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadPowered(context),
        ),
      Align(
        alignment: Alignment.center,
        child: loadLogo(),
      ),
      if (usesWorkspaceStyle && !bind.isCustomClient())
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
            child: Row(children: [
              loadIcon(28),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(bind.mainGetAppNameSync(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium)),
            ])),
      buildTip(context),
      if (!isOutgoingOnly)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: WorkspacePanel(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              buildIDBoard(context),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Divider(height: 1),
              ),
              buildPasswordBoard(context),
            ]),
          ),
        ),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6)
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: WorkspaceSidebar(
        width: isIncomingOnly ? 280 : 248,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _leftPaneScrollController,
                    child: Column(
                      key: _childKey,
                      children: children,
                    ),
                  ),
                ),
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 25,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate("ID"),
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.color
                                  ?.withOpacity(0.5)),
                        ).marginOnly(top: 5),
                        buildPopupMenu(context)
                      ],
                    ),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      },
                      child: TextFormField(
                        controller: model.serverId,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        style: TextStyle(
                          fontSize: 22,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 52,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              filled: false,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      if (!bind.isDisableSettings())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse(BrandLinks.downloadUrl);
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          // macOS shows the request prompt only once per app, so later
          // presses would do nothing without opening the settings pane.
          launchUrl(Uri.parse(
              'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      final quitButtonText =
          bind.mainGetBuildinOption(key: kOptionQuitButtonText).trim();
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child:
              Text(quitButtonText.isEmpty ? translate('Quit') : quitButtonText),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    if (usesWorkspaceStyle) {
      final theme = Theme.of(context);
      final message = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(translate(title), style: theme.textTheme.labelLarge),
            if (content.isNotEmpty)
              Text(translate(content), style: theme.textTheme.bodySmall),
          ]);
      final actions = Wrap(children: [
        if (btnText.isNotEmpty)
          TextButton(onPressed: onPressed, child: Text(translate(btnText))),
        if (help != null && link != null)
          TextButton(
              onPressed: () => launchUrl(Uri.parse(link)),
              child: Text(translate(help))),
        if (closeButton == true)
          IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close_rounded, size: 16),
              onPressed: closeCard),
      ]);
      return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor)),
          child: LayoutBuilder(
              builder: (_, bounds) => Row(children: [
                    Icon(
                        title == 'Permissions'
                            ? Icons.verified_user_outlined
                            : Icons.info_outline_rounded,
                        size: 17,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                        child: bounds.maxWidth < 390
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [message, actions])
                            : Row(children: [
                                Expanded(child: message),
                                ConstrainedBox(
                                    constraints: BoxConstraints(
                                        maxWidth: bounds.maxWidth * .45),
                                    child: actions),
                              ])),
                  ])));
    }
    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _hardwareKeyboard.addHandler(_handleGlobalKeyEvent);
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse:
          return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
            "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
          loginMethod: call.arguments['loginMethod'] ?? '',
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance
            .bumpMouse(dx: call.arguments['dx'], dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _hardwareKeyboard.removeHandler(_handleGlobalKeyEvent);
    _leftPaneScrollController.dispose();
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
      if (isMacOS && usesWorkspaceStyle) setState(() {});
    }
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
