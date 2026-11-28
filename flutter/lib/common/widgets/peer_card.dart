import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_hbb/common/widgets/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/device_profile.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;
import '../../desktop/widgets/popup_menu.dart';
import '../../mobile/pages/phone_microphone_page.dart';
import 'dart:math' as math;

typedef PopupMenuEntryBuilder = Future<List<mod_menu.PopupMenuEntry<String>>>
    Function(BuildContext);

enum PeerUiType { grid, tile, list }

final peerCardUiType = PeerUiType.grid.obs;

bool _canConnectPhoneMicrophone(Peer peer) =>
    !isWeb &&
    isMobile &&
    (peer.platform == kPeerPlatformWindows ||
        peer.platform == kPeerPlatformMacOS ||
        peer.platform.isEmpty);

class ConnectionPeerList extends InheritedWidget {
  const ConnectionPeerList({super.key, this.onConnect, required super.child});

  final void Function(Peer, PeerTabIndex)? onConnect;

  static ConnectionPeerList? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnectionPeerList>();

  @override
  bool updateShouldNotify(ConnectionPeerList oldWidget) =>
      onConnect != oldWidget.onConnect;
}

bool? hideUsernameOnCard;

class _PeerCard extends StatefulWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final Function(BuildContext, String) connect;
  final PopupMenuEntryBuilder popupMenuEntryBuilder;

  const _PeerCard(
      {required this.peer,
      required this.tab,
      required this.connect,
      required this.popupMenuEntryBuilder,
      Key? key})
      : super(key: key);

  @override
  _PeerCardState createState() => _PeerCardState();
}

/// State for the connection page.
class _PeerCardState extends State<_PeerCard> {
  var _menuPos = RelativeRect.fill;
  final double _cardRadius = 16;
  final double _tileRadius = 12;
  final double _borderWidth = 2;

  @override
  Widget build(BuildContext context) {
    final onConnect = ConnectionPeerList.of(context)?.onConnect;
    if (usesWorkspaceStyle) {
      final isPhonePlatform = !isWeb &&
          (Theme.of(context).platform == TargetPlatform.iOS ||
              Theme.of(context).platform == TargetPlatform.android);
      final (multiSelectionMode, isSelected) =
          context.select<PeerTabModel, (bool, bool)>(
              (m) => (m.multiSelectionMode, m.isPeerSelected(widget.peer.id)));
      return isPhonePlatform
          ? _workspaceCard(onConnect,
              multiSelectionMode: multiSelectionMode, isSelected: isSelected)
          : Obx(() => _workspaceCard(onConnect,
              multiSelectionMode: multiSelectionMode, isSelected: isSelected));
    }
    if (onConnect != null) return _connectionRow(onConnect);
    return Obx(() =>
        stateGlobal.isPortrait.isTrue ? _buildPortrait() : _buildLandscape());
  }

  Widget _workspaceCard(
    void Function(Peer, PeerTabIndex)? onConnect, {
    required bool multiSelectionMode,
    required bool isSelected,
  }) {
    final peer = widget.peer;
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final host = [
      if (hideUsernameOnCard != true && peer.username.isNotEmpty) peer.username,
      if (peer.hostname.isNotEmpty) peer.hostname,
    ].join('@');
    final isPhonePlatform =
        Theme.of(context).platform == TargetPlatform.iOS ||
            Theme.of(context).platform == TargetPlatform.android;
    final grid = !isPhonePlatform &&
        !stateGlobal.isPortrait.value &&
        peerCardUiType.value == PeerUiType.grid;
    Widget desktopAction(String label, IconData icon, VoidCallback onPressed,
            {bool primary = false}) =>
        grid
            ? TextButton(
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: primary
                        ? Theme.of(context).colorScheme.primary
                        : WorkspaceStyle.elevatedSurface(context),
                    foregroundColor: primary
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    textStyle: const TextStyle(fontSize: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6))),
                onPressed: onPressed,
                child: Text(translate(label)))
            : IconButton(
                tooltip: translate(label),
                visualDensity: VisualDensity.compact,
                icon: Icon(icon, size: 18),
                onPressed: onPressed);
    final card = DeviceCard(
      name: peer.alias.isNotEmpty
          ? peer.alias
          : host.isNotEmpty
              ? host
              : formatID(peer.id),
      remoteId: formatID(peer.id),
      platform: peer.platform,
      platformIcon: switch (peer.platform.toLowerCase()) {
        'mac os' || 'macos' || 'darwin' => Icons.grid_view_outlined,
        'windows' => Icons.window_outlined,
        'linux' => Icons.terminal_rounded,
        'android' || 'ios' => Icons.smartphone_outlined,
        _ => _deviceIcon(peer),
      },
      online: peer.online,
      status: translate(peer.online ? 'Online' : 'Offline'),
      details: host,
      note: _showNote(peer) ? peer.note : '',
      tags: peer.tags.map((tag) => tag.toString()).toList(),
      grid: grid,
      selected: isSelected,
      passwordSaved: _shouldBuildPasswordIcon(peer),
      actions: [
        if (!multiSelectionMode && !isPhonePlatform) ...[
          desktopAction(
              'Transfer file',
              Icons.folder_outlined,
              () => connectInPeerTab(context, peer, widget.tab,
                  isFileTransfer: true)),
          desktopAction(
              'Terminal',
              Icons.terminal_rounded,
              () => connectInPeerTab(context, peer, widget.tab,
                  isTerminal: true)),
          desktopAction('Connect', Icons.arrow_forward_rounded,
              () => connectInPeerTab(context, peer, widget.tab),
              primary: true),
        ] else if (!multiSelectionMode)
          IconButton(
            tooltip: translate('Transfer file'),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            icon: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: WorkspaceStyle.elevatedSurface(context),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.folder_outlined,
                  size: 14, color: Theme.of(context).hintColor),
            ),
            onPressed: () => connectInPeerTab(context, peer, widget.tab,
                isFileTransfer: true),
          ),
        if (!multiSelectionMode && _canConnectPhoneMicrophone(peer))
          IconButton(
            tooltip: translate('Audio mode'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.headset_mic_outlined, size: 18),
            onPressed: () => PhoneMicrophonePage.open(context, peer.id),
          ),
        if (!multiSelectionMode)
          Builder(builder: (menuContext) => IconButton(
            tooltip: translate('More'),
            visualDensity: VisualDensity.compact,
            constraints: grid
                ? const BoxConstraints.tightFor(width: 28, height: 28)
                : null,
            padding: grid ? EdgeInsets.zero : null,
            icon: Icon(Icons.more_horiz, size: 20,
                color: Theme.of(context).hintColor),
            onPressed: () {
              final box = menuContext.findRenderObject() as RenderBox;
              final position = box.localToGlobal(box.size.bottomLeft(Offset.zero));
              _menuPos = RelativeRect.fromLTRB(
                  position.dx, position.dy, position.dx, position.dy);
              _showPeerMenu(peer.id);
            },
          ))
        else if (stateGlobal.isPortrait.value)
          checkBoxOrActionMorePortrait(peer)
        else
          checkBoxOrActionMoreLandscape(peer, isTile: !grid),
      ],
    );
    void openMenu(Offset position) {
      _menuPos = RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy);
      _showPeerMenu(peer.id);
    }

    final child = onConnect == null
        ? gestureDetector(child: card)
        : GestureDetector(
            onTap: () {
              final model = context.read<PeerTabModel>();
              if (model.multiSelectionMode) {
                model.select(peer);
              } else {
                onConnect(peer, widget.tab);
              }
            },
            onLongPress: () => context.read<PeerTabModel>().select(peer),
            child: card,
          );
    return GestureDetector(
        onSecondaryTapDown: (event) => openMenu(event.globalPosition),
        child: MouseRegion(cursor: SystemMouseCursors.click, child: child));
  }

  Widget _connectionRow(void Function(Peer, PeerTabIndex) onConnect) {
    final peer = widget.peer;
    final theme = Theme.of(context);
    final model = Provider.of<PeerTabModel>(context);
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final host = [
      if (hideUsernameOnCard != true && peer.username.isNotEmpty) peer.username,
      if (peer.hostname.isNotEmpty) peer.hostname,
    ].join('@');
    final id = formatID(peer.id);
    final name = peer.alias.isNotEmpty
        ? peer.alias
        : host.isNotEmpty
            ? host
            : id;
    final details = [
      if (name != id) id,
      if (host.isNotEmpty && name != host) host,
      if (_showNote(peer)) peer.note,
    ];
    final selected = model.multiSelectionMode && model.isPeerSelected(peer.id);
    void activate() {
      if (model.multiSelectionMode) {
        model.select(peer);
      } else {
        onConnect(peer, widget.tab);
      }
    }

    void openMenu(Offset position) {
      _menuPos = RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy);
      _showPeerMenu(peer.id);
    }

    return Material(
        color:
            selected ? theme.colorScheme.secondaryContainer : theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: activate,
            onDoubleTap: model.multiSelectionMode ? null : activate,
            onSecondaryTapDown: (details) => openMenu(details.globalPosition),
            child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
                child: Row(children: [
                  Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(_deviceIcon(peer),
                          size: 19,
                          color: theme.colorScheme.primary,
                          semanticLabel: peer.platform)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Tooltip(
                    message: [name, ...details, ...peer.tags].join(' · '),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          if (details.isNotEmpty)
                            Text(details.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor)),
                        ]),
                  )),
                  if (_shouldBuildPasswordIcon(peer))
                    const Icon(Icons.key_rounded, size: 14),
                  getOnline(7, peer.online),
                  Text(translate(peer.online ? 'Online' : 'Offline'),
                      style: theme.textTheme.labelSmall),
                  const SizedBox(width: 8),
                  if (model.multiSelectionMode)
                    checkBoxOrActionMoreLandscape(peer, isTile: true)
                  else
                    Builder(
                        builder: (menuContext) => IconButton(
                            tooltip: translate('More'),
                            icon:
                                const Icon(Icons.more_horiz_rounded, size: 20),
                            onPressed: () {
                              final box =
                                  menuContext.findRenderObject() as RenderBox;
                              openMenu(box.localToGlobal(
                                  box.size.bottomLeft(Offset.zero)));
                            })),
                ]))));
  }

  Widget gestureDetector({required Widget child}) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final peer = super.widget.peer;
    return GestureDetector(
        // Web card actions have their own semantics; preserve pointer double-clicks.
        excludeFromSemantics: isWebDesktop,
        onDoubleTap: peerTabModel.multiSelectionMode
            ? null
            : () => widget.connect(context, peer.id),
        onTap: () {
          if (peerTabModel.multiSelectionMode) {
            peerTabModel.select(peer);
          } else {
            if (isMobile) {
              widget.connect(context, peer.id);
            } else {
              peerTabModel.select(peer);
            }
          }
        },
        onLongPress: () => peerTabModel.select(peer),
        child: child);
  }

  Widget _buildPortrait() {
    final peer = super.widget.peer;
    if (!isWeb && Theme.of(context).platform == TargetPlatform.iOS) {
      return DecoratedBox(
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor))),
          child: gestureDetector(
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: _buildPeerTile(context, peer, null))));
    }
    return Card(
        margin: EdgeInsets.symmetric(horizontal: 2),
        child: gestureDetector(
          child: Container(
              padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
              child: _buildPeerTile(context, peer, null)),
        ));
  }

  Widget _buildLandscape() {
    final peer = super.widget.peer;
    var deco = Rx<BoxDecoration?>(
      BoxDecoration(
        border: Border.all(color: Colors.transparent, width: _borderWidth),
        borderRadius: BorderRadius.circular(
          peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
        ),
      ),
    );
    return MouseRegion(
      onEnter: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: _borderWidth),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      onExit: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(color: Colors.transparent, width: _borderWidth),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      child: gestureDetector(
          child: Obx(() => peerCardUiType.value == PeerUiType.grid
              ? _buildPeerCard(context, peer, deco)
              : _buildPeerTile(context, peer, deco))),
    );
  }

  bool _showNote(Peer peer) {
    return peerTabShowNote(widget.tab) && peer.note.isNotEmpty;
  }

  makeChild(bool isPortrait, Peer peer) {
    final name = hideUsernameOnCard == true
        ? peer.hostname
        : '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    if (isPortrait && !isWeb && Theme.of(context).platform == TargetPlatform.iOS) {
      return _iPhonePeerRow(peer, name);
    }
    final greyStyle = TextStyle(
        fontSize: 11,
        color: Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.6));
    final showNote = _showNote(peer);

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
            decoration: BoxDecoration(
              color: usesWorkspaceStyle ? WorkspaceStyle.navy : str2color('${peer.id}${peer.platform}', 0x7f),
              borderRadius: isPortrait
                  ? BorderRadius.circular(_tileRadius)
                  : BorderRadius.only(
                      topLeft: Radius.circular(_tileRadius),
                      bottomLeft: Radius.circular(_tileRadius),
                    ),
            ),
            alignment: Alignment.center,
            width: isPortrait ? 50 : 42,
            height: isPortrait ? 50 : null,
            child: Stack(
              children: [
                getPlatformImage(peer.platform, size: isPortrait ? 38 : 30)
                    .paddingAll(6),
                if (_shouldBuildPasswordIcon(peer))
                  Positioned(
                    top: 1,
                    left: 1,
                    child: Icon(Icons.key, size: 6, color: Colors.white),
                  ),
              ],
            )),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: usesWorkspaceStyle ? Theme.of(context).cardColor : Theme.of(context).colorScheme.background,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(_tileRadius),
                bottomRight: Radius.circular(_tileRadius),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Row(children: [
                        getOnline(isPortrait ? 4 : 8, peer.online),
                        Expanded(
                            child: Text(
                          peer.alias.isEmpty ? formatID(peer.id) : peer.alias,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        )),
                      ]).marginOnly(top: isPortrait ? 0 : 2),
                      Row(
                        children: [
                          Flexible(
                            child: Tooltip(
                              message: name,
                              waitDuration: const Duration(seconds: 1),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  name,
                                  style: isPortrait ? null : greyStyle,
                                  textAlign: TextAlign.start,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          if (showNote)
                            Expanded(
                              child: Tooltip(
                                message: peer.note,
                                waitDuration: const Duration(seconds: 1),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    peer.note,
                                    style: isPortrait ? null : greyStyle,
                                    textAlign: TextAlign.start,
                                    overflow: TextOverflow.ellipsis,
                                  ).marginOnly(
                                      left: peerCardUiType.value ==
                                              PeerUiType.list
                                          ? 32
                                          : 4),
                                ),
                              ),
                            )
                        ],
                      ),
                    ],
                  ).marginOnly(top: 2),
                ),
                isPortrait
                    ? checkBoxOrActionMorePortrait(peer)
                    : checkBoxOrActionMoreLandscape(peer, isTile: true),
              ],
            ).paddingOnly(left: 10.0, top: 3.0),
          ),
        )
      ],
    );
  }

  Widget _iPhonePeerRow(Peer peer, String host) {
    final theme = Theme.of(context);
    final name = peer.alias.isNotEmpty ? peer.alias : host;
    final status = translate(peer.online ? 'Online' : 'Offline');
    final details = [
      if (name.isNotEmpty) formatID(peer.id),
      if (host.isNotEmpty && host != name) host,
    ];
    final statusLabel = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(peer.online ? Icons.circle : Icons.circle_outlined,
          size: 8,
          color: peer.online
              ? (theme.brightness == Brightness.dark
                  ? const Color(0xff73d8ad)
                  : const Color(0xff177856))
              : theme.hintColor),
      const SizedBox(width: 5),
      Flexible(
          child: Text(status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.hintColor))),
    ]);
    return LayoutBuilder(builder: (context, bounds) {
      final statusAtEnd = bounds.maxWidth >= 342 &&
          MediaQuery.textScalerOf(context).scale(14) <= 16;
      return Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(13)),
          child: Icon(_deviceIcon(peer),
              color: theme.colorScheme.primary,
              size: 24,
              semanticLabel: peer.platform),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                  child: Text(name.isEmpty ? formatID(peer.id) : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium)),
              if (_shouldBuildPasswordIcon(peer)) ...[
                const SizedBox(width: 4),
                const Icon(Icons.key_rounded, size: 14),
              ],
            ]),
            if (details.isNotEmpty)
              Text(details.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            if (_showNote(peer))
              Text(peer.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            if (!statusAtEnd) statusLabel,
          ],
        )),
        if (statusAtEnd) ...[
          const SizedBox(width: 6),
          ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bounds.maxWidth * .25),
              child: statusLabel),
        ],
        checkBoxOrActionMorePortrait(peer),
      ]);
    });
  }

  IconData _deviceIcon(Peer peer) => switch (peer.platform) {
        kPeerPlatformMacOS => Icons.desktop_mac_outlined,
        kPeerPlatformWindows => Icons.laptop_windows_outlined,
        kPeerPlatformAndroid => Icons.phone_android_rounded,
        kPeerPlatformLinux => Icons.dns_outlined,
        _ => Icons.devices_outlined,
      };

  Widget _buildPeerTile(
      BuildContext context, Peer peer, Rx<BoxDecoration?>? deco) {
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final colors = _frontN(peer.tags, 25)
        .map((e) => gFFI.abModel.getCurrentAbTagColor(e))
        .toList();
    return Tooltip(
      message: !(isDesktop || isWebDesktop)
          ? ''
          : peer.tags.isNotEmpty
              ? '${translate('Tags')}: ${peer.tags.join(', ')}'
              : '',
      child: Stack(children: [
        Obx(
          () => deco == null
              ? makeChild(stateGlobal.isPortrait.isTrue, peer)
              : Container(
                  foregroundDecoration: deco.value,
                  child: makeChild(stateGlobal.isPortrait.isTrue, peer),
                ),
        ),
        if (colors.isNotEmpty)
          Obx(() => Positioned(
                top: 2,
                right: stateGlobal.isPortrait.isTrue ? 20 : 10,
                child: CustomPaint(
                  painter: TagPainter(radius: 3, colors: colors),
                ),
              ))
      ]),
    );
  }

  Widget _buildPeerCard(
      BuildContext context, Peer peer, Rx<BoxDecoration?> deco) {
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final name = hideUsernameOnCard == true
        ? peer.hostname
        : '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    final child = Card(
      color: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      // to-do: memory leak here, more investigation needed.
      // Continious rebuilds of `Obx()` will cause memory leak here.
      // The simple demo does not have this issue.
      child: Obx(
        () => Container(
          foregroundDecoration: deco.value,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_cardRadius - _borderWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    color: usesWorkspaceStyle ? WorkspaceStyle.navy : str2color('${peer.id}${peer.platform}', 0x7f),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                child:
                                    getPlatformImage(peer.platform, size: 60),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Tooltip(
                                      message: name,
                                      waitDuration: const Duration(seconds: 1),
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_showNote(peer))
                                Row(
                                  children: [
                                    Expanded(
                                        child: Tooltip(
                                      message: peer.note,
                                      waitDuration: const Duration(seconds: 1),
                                      child: Text(
                                        peer.note,
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                  ],
                                ),
                            ],
                          ).paddingOnly(top: 4.0, left: 4.0, right: 4.0),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: usesWorkspaceStyle ? Theme.of(context).cardColor : Theme.of(context).colorScheme.background,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                          child: Row(children: [
                        getOnline(8, peer.online),
                        Expanded(
                            child: Text(
                          peer.alias.isEmpty ? formatID(peer.id) : peer.alias,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        )),
                      ]).paddingSymmetric(vertical: 8)),
                      checkBoxOrActionMoreLandscape(peer, isTile: false),
                    ],
                  ).paddingSymmetric(horizontal: 12.0),
                )
              ],
            ),
          ),
        ),
      ),
    );

    final colors = _frontN(peer.tags, 25)
        .map((e) => gFFI.abModel.getCurrentAbTagColor(e))
        .toList();
    return Tooltip(
      message: peer.tags.isNotEmpty
          ? '${translate('Tags')}: ${peer.tags.join(', ')}'
          : '',
      child: Stack(children: [
        child,
        if (_shouldBuildPasswordIcon(peer))
          Positioned(
            top: 4,
            left: 12,
            child: Icon(Icons.key, size: 12, color: Colors.white),
          ),
        if (colors.isNotEmpty)
          Positioned(
            top: 4,
            right: 12,
            child: CustomPaint(
              painter: TagPainter(radius: 4, colors: colors),
            ),
          )
      ]),
    );
  }

  List _frontN<T>(List list, int n) {
    if (list.length <= n) {
      return list;
    } else {
      return list.sublist(0, n);
    }
  }

  Widget checkBoxOrActionMorePortrait(Peer peer) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      final checkbox = Padding(
        padding: const EdgeInsets.all(12),
        child: selected
            ? Icon(
                Icons.check_box,
                color: Theme.of(context).colorScheme.primary,
              )
            : Icon(Icons.check_box_outline_blank),
      );
      return isWebDesktop
          ? Semantics(
              container: true,
              label: formatID(peer.id),
              checked: selected,
              onTap: () => peerTabModel.select(peer),
              child: checkbox)
          : checkbox;
    } else {
      if (isWebDesktop) return _actionMoreWeb(peer);
      return InkWell(
          child: const Padding(
              padding: EdgeInsets.all(12), child: Icon(Icons.more_vert)),
          onTapDown: (e) {
            final x = e.globalPosition.dx;
            final y = e.globalPosition.dy;
            _menuPos = RelativeRect.fromLTRB(x, y, x, y);
          },
          onTap: () {
            _showPeerMenu(peer.id);
          });
    }
  }

  Widget checkBoxOrActionMoreLandscape(Peer peer, {required bool isTile}) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      final icon = selected
          ? Icon(
              Icons.check_box,
              color: Theme.of(context).colorScheme.primary,
            )
          : Icon(Icons.check_box_outline_blank);
      final checkbox = isWebDesktop
          ? Semantics(
              container: true,
              label: formatID(peer.id),
              checked: selected,
              onTap: () => peerTabModel.select(peer),
              child: icon)
          : icon;
      bool last = peerTabModel.isShiftDown && peer.id == peerTabModel.lastId;
      double right = isTile ? 4 : 0;
      if (last) {
        return Container(
          decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 1)),
          child: checkbox,
        ).marginOnly(right: right);
      } else {
        return checkbox.marginOnly(right: right);
      }
    } else {
      return isWebDesktop ? _actionMoreWeb(peer) : _actionMore(peer);
    }
  }

  Widget _actionMore(Peer peer) => Listener(
      onPointerDown: (e) {
        final x = e.position.dx;
        final y = e.position.dy;
        _menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      onPointerUp: (_) => _showPeerMenu(peer.id),
      child: build_more(context));

  Widget _actionMoreWeb(Peer peer) => Semantics(
      container: true,
      button: true,
      label: translate('More'),
      child: Builder(
          builder: (context) => build_more(context, onTap: () {
                final box = context.findRenderObject() as RenderBox;
                final position =
                    box.localToGlobal(box.size.center(Offset.zero));
                _menuPos = RelativeRect.fromLTRB(
                    position.dx, position.dy, position.dx, position.dy);
                _showPeerMenu(peer.id);
              })));

  bool _shouldBuildPasswordIcon(Peer peer) {
    if (gFFI.peerTabModel.currentTab != PeerTabIndex.ab.index) return false;
    if (gFFI.abModel.current.isPersonal()) return false;
    return peer.password.isNotEmpty;
  }

  /// Show the peer menu and handle user's choice.
  /// User might remove the peer or send a file to the peer.
  void _showPeerMenu(String id) async {
    await mod_menu.showMenu(
      context: context,
      position: _menuPos,
      items: await super.widget.popupMenuEntryBuilder(context),
      elevation: 8,
    );
  }
}

abstract class BasePeerCard extends StatelessWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final EdgeInsets? menuPadding;

  BasePeerCard(
      {required this.peer, required this.tab, this.menuPadding, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _PeerCard(
      peer: peer,
      tab: tab,
      connect: (BuildContext context, String id) =>
          connectInPeerTab(context, peer, tab),
      popupMenuEntryBuilder: _buildPopupMenuEntry,
    );
  }

  Future<List<mod_menu.PopupMenuEntry<String>>> _buildPopupMenuEntry(
          BuildContext context) async =>
      (await _buildMenuItems(context))
          .map((e) => e.build(
              context,
              const MenuConfig(
                  commonColor: CustomPopupMenuTheme.commonColor,
                  height: CustomPopupMenuTheme.height,
                  dividerHeight: CustomPopupMenuTheme.dividerHeight)))
          .expand((i) => i)
          .toList();

  @protected
  Future<List<MenuEntryBase<String>>> _buildMenuItems(BuildContext context);

  @protected
  Future<List<MenuEntryBase<String>>> _buildConnectionMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      if (_canConnectPhoneMicrophone(peer))
        MenuEntryButton<String>(
          childBuilder: (style) =>
              Text(translate('Audio mode'), style: style),
          proc: () => PhoneMicrophonePage.open(context, peer.id),
          padding: menuPadding,
          dismissOnClicked: true,
        ),
      _transferFileAction(context),
      _viewCameraAction(context),
      _terminalAction(context),
      if (!isWeb)
        MenuEntryButton<String>(
          childBuilder: (style) => Text(translate('Settings'), style: style),
          proc: () => showDeviceProfileDialog(
            context,
            peerId: peer.id,
            peerTitle: peer.alias.isNotEmpty
                ? peer.alias
                : (peer.hostname.isNotEmpty ? peer.hostname : formatID(peer.id)),
          ),
          padding: menuPadding,
          dismissOnClicked: true,
        ),
    ];

    if (peer.platform == kPeerPlatformWindows) {
      menuItems.add(_terminalRunAsAdminAction(context));
    }

    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context));
    }
    if (isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    menuItems.add(MenuEntryDivider<String>());
    menuItems.add(_requestApprovalAction(context));
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    if (!isWeb) {
      menuItems.add(await _forceAlwaysRelayAction(peer.id));
    }
    return menuItems;
  }

  MenuEntryButton<String> _connectCommonAction(
    BuildContext context,
    String title, {
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTcpTunneling = false,
    bool isRDP = false,
    bool isTerminal = false,
    bool isTerminalRunAsAdmin = false,
    String loginMethod = '',
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(title, style: style),
      proc: () {
        if (isTerminalRunAsAdmin) {
          setEnvTerminalAdmin();
        }
        connectInPeerTab(
          context,
          peer,
          tab,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTcpTunneling: isTcpTunneling,
          isRDP: isRDP,
          isTerminal: isTerminal || isTerminalRunAsAdmin,
          useDeviceDefault: false,
          loginMethod: loginMethod,
        );
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  MenuEntryBase<String> _requestApprovalAction(BuildContext context) {
    MenuEntryButton<String> action(String title,
            {bool isFileTransfer = false,
            bool isViewCamera = false,
            bool isTcpTunneling = false,
            bool isRDP = false,
            bool isTerminal = false,
            bool isTerminalRunAsAdmin = false}) =>
        _connectCommonAction(
          context,
          isTerminal || isTerminalRunAsAdmin
              ? '${translate(title)} (beta)'
              : translate(title),
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTcpTunneling: isTcpTunneling,
          isRDP: isRDP,
          isTerminal: isTerminal,
          isTerminalRunAsAdmin: isTerminalRunAsAdmin,
          loginMethod: 'request-approval',
        );

    return MenuEntrySubMenu<String>(
      text: translate('Request approval'),
      dismissParentOnCanceled: true,
      arrowScale: 1.0,
      padding: menuPadding,
      entries: [
        action('Connect'),
        action('Transfer file', isFileTransfer: true),
        action('View camera', isViewCamera: true),
        action('Terminal', isTerminal: true),
        if (peer.platform == kPeerPlatformWindows)
          action('Terminal (Run as administrator)', isTerminalRunAsAdmin: true),
        if (isDesktop && peer.platform != kPeerPlatformAndroid)
          action('TCP tunneling', isTcpTunneling: true),
        if (isWindows && peer.platform == kPeerPlatformWindows)
          action('RDP', isRDP: true),
      ],
    );
  }

  @protected
  MenuEntryBase<String> _connectAction(BuildContext context) {
    return _connectCommonAction(
      context,
      peer.alias.isEmpty
          ? translate('Connect')
          : '${translate('Connect')} ${peer.id}',
    );
  }

  @protected
  MenuEntryBase<String> _transferFileAction(BuildContext context) {
    return _connectCommonAction(
      context,
      translate('Transfer file'),
      isFileTransfer: true,
    );
  }

  @protected
  MenuEntryBase<String> _viewCameraAction(BuildContext context) {
    return _connectCommonAction(
      context,
      translate('View camera'),
      isViewCamera: true,
    );
  }

  @protected
  MenuEntryBase<String> _terminalAction(BuildContext context) {
    return _connectCommonAction(
      context,
      '${translate('Terminal')} (beta)',
      isTerminal: true,
    );
  }

  @protected
  MenuEntryBase<String> _terminalRunAsAdminAction(BuildContext context) {
    return _connectCommonAction(
      context,
      '${translate('Terminal (Run as administrator)')} (beta)',
      isTerminalRunAsAdmin: true,
    );
  }

  @protected
  MenuEntryBase<String> _tcpTunnelingAction(BuildContext context) {
    return _connectCommonAction(
      context,
      translate('TCP tunneling'),
      isTcpTunneling: true,
    );
  }

  @protected
  MenuEntryBase<String> _rdpAction(BuildContext context, String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Container(
          alignment: AlignmentDirectional.center,
          height: CustomPopupMenuTheme.height,
          child: Row(
            children: [
              Text(
                translate('RDP'),
                style: style,
              ),
              Expanded(
                  child: Align(
                alignment: Alignment.centerRight,
                child: Transform.scale(
                    scale: 0.8,
                    child: IconButton(
                      icon: const Icon(Icons.edit),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: kMinInteractiveDimension - 8,
                        minHeight: kMinInteractiveDimension,
                      ),
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                        _rdpDialog(id);
                      },
                    )),
              ))
            ],
          )),
      proc: () {
        connectInPeerTab(context, peer, tab, isRDP: true);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _wolAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('WOL'),
        style: style,
      ),
      proc: () {
        bind.mainWol(id: id);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  /// Only available on Windows.
  @protected
  MenuEntryBase<String> _createShortCutAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Create desktop shortcut'),
        style: style,
      ),
      proc: () {
        bind.mainCreateShortcut(id: id);
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  Future<MenuEntryBase<String>> _openNewConnInAction(
      String id, String label, String key) async {
    return MenuEntrySwitch<String>(
      switchType: SwitchType.scheckbox,
      text: translate(label),
      getter: () async => mainGetPeerBoolOptionSync(id, key),
      setter: (bool v) async {
        await bind.mainSetPeerOption(
            id: id, key: key, value: bool2option(key, v));
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  _openInTabsAction(String id) async =>
      await _openNewConnInAction(id, 'Open in New Tab', kOptionOpenInTabs);

  _openInWindowsAction(String id) async => await _openNewConnInAction(
      id, 'Open in new window', kOptionOpenInWindows);

  // ignore: unused_element
  _openNewConnInOptAction(String id) async =>
      mainGetLocalBoolOptionSync(kOptionOpenNewConnInTabs)
          ? await _openInWindowsAction(id)
          : await _openInTabsAction(id);

  @protected
  Future<bool> _isForceAlwaysRelay(String id) async {
    return option2bool(kOptionForceAlwaysRelay,
        (await bind.mainGetPeerOption(id: id, key: kOptionForceAlwaysRelay)));
  }

  @protected
  Future<MenuEntryBase<String>> _forceAlwaysRelayAction(String id) async {
    return MenuEntrySwitch<String>(
      switchType: SwitchType.scheckbox,
      text: translate('Always connect via relay'),
      getter: () async {
        return await _isForceAlwaysRelay(id);
      },
      setter: (bool v) async {
        await bind.mainSetPeerOption(
            id: id,
            key: kOptionForceAlwaysRelay,
            value: bool2option(kOptionForceAlwaysRelay, v));
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _renameAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Rename'),
        style: style,
      ),
      proc: () async {
        String oldName = await _getAlias(id);
        renameDialog(
            oldName: oldName,
            onSubmit: (String newName) async {
              if (newName != oldName) {
                if (tab == PeerTabIndex.ab) {
                  await gFFI.abModel.changeAlias(id: id, alias: newName);
                  await bind.mainSetPeerAlias(id: id, alias: newName);
                } else {
                  await bind.mainSetPeerAlias(id: id, alias: newName);
                  showToast(translate('Successful'));
                  _update();
                }
              }
            });
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _removeAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Delete'),
            style: style?.copyWith(color: Colors.red),
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.delete_forever, color: Colors.red),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        onSubmit() async {
          switch (tab) {
            case PeerTabIndex.recent:
              await bind.mainRemovePeer(id: id);
              bind.mainLoadRecentPeers();
              break;
            case PeerTabIndex.fav:
              final favs = (await bind.mainGetFav()).toList();
              if (favs.remove(id)) {
                await bind.mainStoreFav(favs: favs);
                bind.mainLoadFavPeers();
              }
              break;
            case PeerTabIndex.lan:
              await bind.mainRemoveDiscovered(id: id);
              bind.mainLoadLanPeers();
              break;
            case PeerTabIndex.ab:
              await gFFI.abModel.deletePeers([id]);
              break;
            case PeerTabIndex.group:
            case PeerTabIndex.owned:
              break;
          }
          if (tab != PeerTabIndex.ab) {
            showToast(translate('Successful'));
          }
        }

        deleteConfirmDialog(onSubmit,
            '${translate('Delete')} "${peer.alias.isEmpty ? formatID(peer.id) : peer.alias}"?');
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _unrememberPasswordAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Forget Password'),
        style: style,
      ),
      proc: () async {
        bool succ = await gFFI.abModel.changePersonalHashPassword(id, '');
        await bind.mainForgetPassword(id: id);
        if (succ) {
          showToast(translate('Successful'));
        } else {
          if (tab.index == PeerTabIndex.ab.index) {
            BotToast.showText(
                contentColor: Colors.red, text: translate("Failed"));
          }
        }
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _addFavAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Add to Favorites'),
            style: style,
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.star_outline),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (!favs.contains(id)) {
            favs.add(id);
            await bind.mainStoreFav(favs: favs);
          }
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _rmFavAction(
      String id, Future<void> Function() reloadFunc) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Remove from Favorites'),
            style: style,
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.star),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (favs.remove(id)) {
            await bind.mainStoreFav(favs: favs);
            await reloadFunc();
          }
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _addToAb(Peer peer) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Add to address book'),
        style: style,
      ),
      proc: () {
        () async {
          addPeersToAbDialog([Peer.copy(peer)]);
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  Future<String> _getAlias(String id) async =>
      await bind.mainGetPeerOption(id: id, key: 'alias');

  @protected
  void _update();
}

class RecentPeerCard extends BasePeerCard {
  RecentPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.recent,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List favs = (await bind.mainGetFav()).toList();

    final menuItems = await _buildConnectionMenuItems(context);
    menuItems.add(MenuEntryDivider());
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    if (isMobile || isDesktop || isWebDesktop) {
      menuItems.add(_renameAction(peer.id));
    }
    if (await bind.mainPeerHasPassword(id: peer.id)) {
      menuItems.add(_unrememberPasswordAction(peer.id));
    }

    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadRecentPeers();
}

class FavoritePeerCard extends BasePeerCard {
  FavoritePeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.fav,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final menuItems = await _buildConnectionMenuItems(context);
    menuItems.add(MenuEntryDivider());
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    if (isMobile || isDesktop || isWebDesktop) {
      menuItems.add(_renameAction(peer.id));
    }
    if (await bind.mainPeerHasPassword(id: peer.id)) {
      menuItems.add(_unrememberPasswordAction(peer.id));
    }
    menuItems.add(_rmFavAction(peer.id, () async {
      await bind.mainLoadFavPeers();
    }));

    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadFavPeers();
}

class DiscoveredPeerCard extends BasePeerCard {
  DiscoveredPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.lan,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List favs = (await bind.mainGetFav()).toList();

    final menuItems = await _buildConnectionMenuItems(context);
    menuItems.add(MenuEntryDivider());
    menuItems.add(_wolAction(peer.id));
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }

    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadLanPeers();
}

class AddressBookPeerCard extends BasePeerCard {
  AddressBookPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.ab,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final menuItems = await _buildConnectionMenuItems(context);
    menuItems.add(MenuEntryDivider());
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    if (gFFI.abModel.current.canWrite()) {
      if (isMobile || isDesktop || isWebDesktop) {
        menuItems.add(_renameAction(peer.id));
      }
      if (gFFI.abModel.current.isPersonal() && peer.hash.isNotEmpty) {
        menuItems.add(_unrememberPasswordAction(peer.id));
      }
      if (!gFFI.abModel.current.isPersonal()) {
        menuItems.add(_changeSharedAbPassword());
      }
      if (gFFI.abModel.currentAbTags.isNotEmpty) {
        menuItems.add(_editTagAction(peer.id));
      }
      menuItems.add(_editNoteAction(peer.id));
    }
    final addressbooks = gFFI.abModel.addressBooksCanWrite();
    if (gFFI.peerTabModel.currentTab == PeerTabIndex.ab.index) {
      addressbooks.remove(gFFI.abModel.currentName.value);
    }
    if (addressbooks.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }
    menuItems.add(_existIn());
    if (gFFI.abModel.current.canWrite()) {
      menuItems.add(MenuEntryDivider());
      menuItems.add(_removeAction(peer.id));
    }
    return menuItems;
  }

  // address book does not need to update
  @protected
  @override
  void _update() =>
      {}; //gFFI.abModel.pullAb(force: ForcePullAb.current, quiet: true);

  @protected
  MenuEntryBase<String> _editTagAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Edit Tag'),
        style: style,
      ),
      proc: () {
        editAbTagDialog(gFFI.abModel.getPeerTags(id), (selectedTag) async {
          await gFFI.abModel.changeTagForPeers([id], selectedTag);
        });
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _editNoteAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Edit note'),
        style: style,
      ),
      proc: () {
        editAbPeerNoteDialog(id);
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  @override
  Future<String> _getAlias(String id) async =>
      gFFI.abModel.find(id)?.alias ?? '';

  MenuEntryBase<String> _changeSharedAbPassword() {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate(
            peer.password.isEmpty ? 'Set shared password' : 'Change Password'),
        style: style,
      ),
      proc: () {
        setSharedAbPasswordDialog(gFFI.abModel.currentName.value, peer);
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }

  MenuEntryBase<String> _existIn() {
    final names = gFFI.abModel.idExistIn(peer.id);
    final text = names.join(', ');
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Exist in'),
        style: style,
      ),
      proc: () {
        gFFI.dialogManager.show((setState, close, context) {
          return CustomAlertDialog(
            title: Text(translate('Exist in')),
            content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(text)]),
            actions: [
              dialogButton(
                "OK",
                icon: Icon(Icons.done_rounded),
                onPressed: close,
              ),
            ],
            onSubmit: close,
            onCancel: close,
          );
        });
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }
}

class MyGroupPeerCard extends BasePeerCard {
  MyGroupPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key,
      PeerTabIndex tab = PeerTabIndex.group})
      : super(
            peer: peer,
            tab: tab,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final menuItems = await _buildConnectionMenuItems(context);
    if (isWindows || gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(MenuEntryDivider());
    }
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    // menuItems.add(MenuEntryDivider());
    // menuItems.add(_renameAction(peer.id));
    // if (await bind.mainPeerHasPassword(id: peer.id)) {
    //   menuItems.add(_unrememberPasswordAction(peer.id));
    // }
    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }
    return menuItems;
  }

  @protected
  @override
  void _update() {
    if (tab == PeerTabIndex.owned) {
      gFFI.userModel.refreshOwnedDevices(force: true);
    } else {
      gFFI.groupModel.pull();
    }
  }
}

void _rdpDialog(String id) async {
  final maxLength = bind.mainMaxEncryptLen();
  final port = await bind.mainGetPeerOption(id: id, key: 'rdp_port');
  final username = await bind.mainGetPeerOption(id: id, key: 'rdp_username');
  final portController = TextEditingController(text: port);
  final userController = TextEditingController(text: username);
  final passwordController = TextEditingController(
      text: await bind.mainGetPeerOption(id: id, key: 'rdp_password'));
  RxBool secure = true.obs;

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      String port = portController.text.trim();
      String username = userController.text;
      String password = passwordController.text;
      await bind.mainSetPeerOption(id: id, key: 'rdp_port', value: port);
      await bind.mainSetPeerOption(
          id: id, key: 'rdp_username', value: username);
      await bind.mainSetPeerOption(
          id: id, key: 'rdp_password', value: password);
      showToast(translate('Successful'));
      close();
    }

    final maxDialogWidth =
        (MediaQuery.sizeOf(context).width - 64).clamp(240.0, 500.0);
    return CustomAlertDialog(
      title: Text(translate('RDP Settings')),
      content: ConstrainedBox(
        constraints: BoxConstraints(
            minWidth: isDesktop ? maxDialogWidth : 0,
            maxWidth: maxDialogWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                isDesktop
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 140),
                        child: Text(
                          "${translate('Port')}:",
                          textAlign: TextAlign.right,
                        ).marginOnly(right: 10))
                    : SizedBox.shrink(),
                Expanded(
                  child: TextField(
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(
                          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'))
                    ],
                    decoration: InputDecoration(
                        labelText: isDesktop ? null : translate('Port'),
                        hintText: '3389'),
                    controller: portController,
                    autofocus: true,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: isDesktop ? 8 : 0),
            Obx(() => Row(
                  children: [
                    stateGlobal.isPortrait.isFalse
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 140),
                            child: Text(
                              "${translate('Username')}:",
                              textAlign: TextAlign.right,
                            ).marginOnly(right: 10))
                        : SizedBox.shrink(),
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                            labelText:
                                isDesktop ? null : translate('Username')),
                        controller: userController,
                      ).workaroundFreezeLinuxMint(),
                    ),
                  ],
                ).marginOnly(bottom: stateGlobal.isPortrait.isFalse ? 8 : 0)),
            Obx(() => Row(
                  children: [
                    stateGlobal.isPortrait.isFalse
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 140),
                            child: Text(
                              "${translate('Password')}:",
                              textAlign: TextAlign.right,
                            ).marginOnly(right: 10))
                        : SizedBox.shrink(),
                    Expanded(
                      child: Obx(() => TextField(
                            obscureText: secure.value,
                            maxLength: maxLength,
                            decoration: InputDecoration(
                                labelText:
                                    isDesktop ? null : translate('Password'),
                                suffixIcon: IconButton(
                                    tooltip: translate(secure.value
                                        ? 'Show'
                                        : 'Hide'),
                                    onPressed: () =>
                                        secure.value = !secure.value,
                                    icon: Icon(secure.value
                                        ? Icons.visibility_off
                                        : Icons.visibility))),
                            controller: passwordController,
                          ).workaroundFreezeLinuxMint()),
                    ),
                  ],
                ))
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  }).whenComplete(() {
    portController.dispose();
    userController.dispose();
    passwordController.dispose();
  });
}

Widget getOnline(double rightPadding, bool online) {
  return Tooltip(
      message: translate(online ? 'Online' : 'Offline'),
      waitDuration: const Duration(seconds: 1),
      child: Padding(
          padding: EdgeInsets.fromLTRB(0, 4, rightPadding, 4),
          child: CircleAvatar(
              radius: 3, backgroundColor: online ? Colors.green : kColorWarn)));
}

Widget build_more(BuildContext context,
    {bool invert = false, VoidCallback? onTap}) {
  final RxBool hover = false.obs;
  final button = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap ?? () {},
      onHover: (value) => hover.value = value,
      child: Obx(() => CircleAvatar(
          radius: 14,
          backgroundColor: hover.value
              ? Theme.of(context).hoverColor
              : (invert
                  ? Theme.of(context).scaffoldBackgroundColor
                  : Colors.transparent),
          child: Icon(Icons.more_vert,
              size: 18,
              color: hover.value
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).hintColor))));
  if (onTap == null) return button;
  // Serial taps preserve cancellation without waiting for the card's double tap.
  return RawGestureDetector(
      excludeFromSemantics: true,
      gestures: {
        SerialTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<SerialTapGestureRecognizer>(
                () => SerialTapGestureRecognizer(
                    allowedButtonsFilter: (buttons) =>
                        buttons == kPrimaryButton),
                (recognizer) => recognizer.onSerialTapUp = (_) => onTap()),
      },
      child: button);
}

class TagPainter extends CustomPainter {
  final double radius;
  late final List<Color> colors;

  TagPainter({required this.radius, required List<Color> colors}) {
    this.colors = colors.reversed.toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    double x = 0;
    double y = radius;
    for (int i = 0; i < colors.length; i++) {
      Paint paint = Paint();
      paint.color = colors[i];
      x -= radius + 1;
      if (i == colors.length - 1) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      } else {
        Path path = Path();
        path.addArc(Rect.fromCircle(center: Offset(x, y), radius: radius),
            math.pi * 4 / 3, math.pi * 4 / 3);
        path.addArc(
            Rect.fromCircle(center: Offset(x - radius, y), radius: radius),
            math.pi * 5 / 3,
            math.pi * 2 / 3);
        path.fillType = PathFillType.evenOdd;
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TagPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        !listEquals(oldDelegate.colors, colors);
  }
}

void connectInPeerTab(BuildContext context, Peer peer, PeerTabIndex tab,
    {bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTcpTunneling = false,
    bool isRDP = false,
    bool isTerminal = false,
    bool useDeviceDefault = true,
    String loginMethod = ''}) async {
  final defaultMode = !isWeb &&
          useDeviceDefault &&
          !isFileTransfer &&
          !isTerminal &&
          !isViewCamera &&
          !isTcpTunneling &&
          !isRDP
      ? loadDeviceProfile(peer.id).defaultMode
      : 'remote';
  var password = '';
  bool isSharedPassword = false;
  if (tab == PeerTabIndex.ab) {
    // If recent peer's alias is empty, set it to ab's alias
    // Because the platform is not set, it may not take effect, but it is more important not to display if the connection is not successful
    if (peer.alias.isNotEmpty &&
        (await bind.mainGetPeerOption(id: peer.id, key: "alias")).isEmpty) {
      await bind.mainSetPeerAlias(
        id: peer.id,
        alias: peer.alias,
      );
    }
    if (!gFFI.abModel.current.isPersonal()) {
      if (peer.password.isNotEmpty) {
        password = peer.password;
        isSharedPassword = true;
      }
      if (password.isEmpty) {
        final abPassword = gFFI.abModel.getdefaultSharedPassword();
        if (abPassword != null) {
          password = abPassword;
          isSharedPassword = true;
        }
      }
    }
  }
  connect(context, peer.id,
      loginMethod: loginMethod,
      password: password,
      isSharedPassword: isSharedPassword,
      isFileTransfer: isFileTransfer || defaultMode == 'file',
      isTerminal: isTerminal || defaultMode == 'terminal',
      isViewCamera: isViewCamera,
      isTcpTunneling: isTcpTunneling,
      isRDP: isRDP);
}
