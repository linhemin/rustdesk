import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter_hbb/common/widgets/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/brand_links.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../mobile_remote_sessions.dart';
import '../phone_microphone.dart';
import 'home_page.dart';
import 'phone_microphone_page.dart';

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.connected_tv);

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    if (isIOS) _allPeersLoader.getAllPeers();
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (mounted &&
            _idController.text.isEmpty &&
            lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    if (isIOS) {
      return IPhoneDeviceWorkspace(
        devices: PeerTabPage(),
        onEnterId: _openConnectionSheet,
        connection: _buildRemoteIDTextField(),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverList(
            delegate: SliverChildListDelegate([
          if (isAndroid) const _ActiveMobileSessions(),
          if (!bind.isCustomClient() && !isIOS)
            Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
          _buildRemoteIDTextField(),
        ])),
        SliverFillRemaining(
          hasScrollBody: true,
          child: PeerTabPage(),
        )
      ],
    ).marginOnly(top: 2, left: 10, right: 10);
  }

  Future<void> _openConnectionSheet() async {
    FocusScope.of(context).unfocus();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _IPhoneConnectionSheet(initialId: _idController.text),
    );
    if (id != null && mounted) {
      _idController.id = id;
      connect(context, id);
    }
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect() {
    var id = _idController.id;
    if (id.isEmpty) return;
    connect(context, id);
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    return updateUrl.isEmpty
        ? const SizedBox(height: 0)
        : InkWell(
            onTap: () async {
              final url = BrandLinks.downloadUrl;
              // https://pub.dev/packages/url_launcher#configuration
              // https://developer.android.com/training/package-visibility/use-cases#open-urls-custom-tabs
              //
              // `await launchUrl(Uri.parse(url))` can also run if skip
              // 1. The following check
              // 2. `<action android:name="android.support.customtabs.action.CustomTabsService" />` in AndroidManifest.xml
              //
              // But it is better to add the check.
              await launchUrl(Uri.parse(url));
            },
            child: Container(
                alignment: AlignmentDirectional.center,
                width: double.infinity,
                color: Colors.pinkAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(translate('Download new version'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))));
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemoteIDTextField() {
    final theme = Theme.of(context);
    final w = SizedBox(
      height: isIOS ? 58 : 80,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: isIOS ? 4 : 8, horizontal: 2),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(isIOS ? 16 : 14),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: EdgeInsets.only(left: 16, right: isIOS ? 0 : 16),
                  child: RawAutocomplete<Peer>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        _autocompleteOpts = const Iterable<Peer>.empty();
                      } else if (_allPeersLoader.peers.isEmpty &&
                          !_allPeersLoader.isPeersLoaded) {
                        Peer emptyPeer = Peer(
                          id: '',
                          username: '',
                          hostname: '',
                          alias: '',
                          platform: '',
                          tags: [],
                          hash: '',
                          password: '',
                          forceAlwaysRelay: false,
                          rdpPort: '',
                          rdpUsername: '',
                          loginName: '',
                          device_group_name: '',
                          note: '',
                        );
                        _autocompleteOpts = [emptyPeer];
                      } else {
                        String textWithoutSpaces =
                            textEditingValue.text.replaceAll(" ", "");
                        if (int.tryParse(textWithoutSpaces) != null) {
                          textEditingValue = TextEditingValue(
                            text: textWithoutSpaces,
                            selection: textEditingValue.selection,
                          );
                        }
                        String textToFind = textEditingValue.text.toLowerCase();

                        _autocompleteOpts = _allPeersLoader.peers
                            .where((peer) =>
                                peer.id.toLowerCase().contains(textToFind) ||
                                peer.username
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.hostname
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.alias.toLowerCase().contains(textToFind))
                            .toList();
                        _allPeersLoader.queryOnlines(_autocompleteOpts);
                      }
                      return _autocompleteOpts;
                    },
                    focusNode: _idFocusNode,
                    textEditingController: _idEditingController,
                    fieldViewBuilder: (BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted) {
                      updateTextAndPreserveSelection(
                          fieldTextEditingController, _idController.text);
                      return AutoSizeTextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        minFontSize: isIOS ? 13 : 18,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: isIOS ? TextInputAction.go : null,
                        // keyboardType: TextInputType.number,
                        onChanged: (String text) {
                          _idController.id = text;
                        },
                        style: TextStyle(
                          fontFamily: isIOS ? 'monospace' : 'WorkSans',
                          fontWeight: isIOS ? FontWeight.w400 : FontWeight.bold,
                          fontSize: isIOS ? 14 : 30,
                          color: isIOS
                              ? theme.colorScheme.onSurface
                              : MyTheme.idColor,
                        ),
                        decoration: InputDecoration(
                          labelText: isIOS ? null : translate('Remote ID'),
                          hintText: isIOS
                              ? translate('Enter remote ID or device name…')
                              : null,
                          filled: isIOS ? false : null,
                          enabledBorder: isIOS ? InputBorder.none : null,
                          focusedBorder: isIOS ? InputBorder.none : null,
                          contentPadding: isIOS ? EdgeInsets.zero : null,
                          // hintText: 'Enter your remote ID',
                          border: InputBorder.none,
                          helperStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: MyTheme.darkGray,
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: 0.2,
                            color: MyTheme.darkGray,
                          ),
                        ),
                        inputFormatters: [IDTextInputFormatter()],
                        onSubmitted: (_) {
                          onConnect();
                        },
                      );
                    },
                    onSelected: (option) {
                      setState(() {
                        _idController.id = option.id;
                        FocusScope.of(context).unfocus();
                      });
                    },
                    optionsViewBuilder: (BuildContext context,
                        AutocompleteOnSelected<Peer> onSelected,
                        Iterable<Peer> options) {
                      options = _autocompleteOpts;
                      double maxHeight = options.length * 50;
                      if (options.length == 1) {
                        maxHeight = 52;
                      } else if (options.length == 3) {
                        maxHeight = 146;
                      } else if (options.length == 4) {
                        maxHeight = 193;
                      }
                      maxHeight = maxHeight.clamp(0, 200);
                      if (isIOS) {
                        final field = _idFocusNode.context?.findRenderObject();
                        if (field is RenderBox && field.hasSize) {
                          // The root overlay does not inherit the keyboard's body resize.
                          final media = MediaQuery.of(context);
                          final available = media.size.height -
                              media.viewInsets.bottom - media.padding.bottom -
                              field.localToGlobal(Offset(0, field.size.height)).dy - 8;
                          maxHeight = maxHeight.clamp(0, available.clamp(0, 200)).toDouble();
                        }
                      }
                      return Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Material(
                                      elevation: 4,
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: maxHeight,
                                            maxWidth: 320,
                                          ),
                                          child: _allPeersLoader
                                                      .peers.isEmpty &&
                                                  !_allPeersLoader.isPeersLoaded
                                              ? Container(
                                                  height: 80,
                                                  child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  )))
                                              : ListView(
                                                  padding:
                                                      EdgeInsets.only(top: 5),
                                                  children: options
                                                      .map((peer) =>
                                                          AutocompletePeerTile(
                                                              onSelect: () =>
                                                                  onSelected(
                                                                      peer),
                                                              peer: peer))
                                                      .toList(),
                                                ))))));
                    },
                  ),
                ),
              ),
              Obx(() => Offstage(
                    offstage: _idEmpty.value,
                    child: IconButton(
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                          });
                        },
                        tooltip: translate('Clear'),
                        icon: Icon(Icons.clear,
                            size: isIOS ? 16 : 24,
                            color: isIOS ? theme.hintColor : MyTheme.darkGray)),
                  )),
              if (isIOS || isAndroid)
                IconButton(
                  icon: const Icon(Icons.headset_mic_outlined),
                  tooltip: translate('Audio mode'),
                  onPressed: () {
                    final audio = PhoneMicrophone.standalone;
                    if (audio != null && _idController.id.isEmpty) {
                      PhoneMicrophonePage.showSession(
                          context, PhoneMicrophone.peerId, audio);
                    } else {
                      PhoneMicrophonePage.open(context, _idController.id);
                    }
                  },
                ),
              if (isIOS)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ElevatedButton(
                    onPressed: onConnect,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(58, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(translate('Connect'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                )
              else
                SizedBox(
                  width: 60,
                  height: 60,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward,
                        color: MyTheme.darkGray, size: 45),
                    onPressed: onConnect,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final child = Column(children: [
      if (isWebDesktop)
        getConnectionPageTitle(context, true)
            .marginOnly(bottom: 10, top: 15, left: 12),
      w
    ]);
    return Align(
        alignment: Alignment.topCenter,
        child: Container(constraints: kMobilePageConstraints, child: child));
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}

/// The command opens the keyboard only when someone wants to enter a new ID.
class _ActiveMobileSessions extends StatelessWidget {
  const _ActiveMobileSessions();

  @override
  Widget build(BuildContext context) => Obx(() {
        final remotes = MobileRemoteSessions.sessions.toList();
        final audio = PhoneMicrophone.standalone;
        if (remotes.isEmpty && audio == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Active sessions'),
                  style: Theme.of(context).textTheme.titleSmall),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (audio != null)
                      AnimatedBuilder(
                        animation: audio.ffiModel,
                        builder: (context, _) => _sessionChip(
                          Icons.headset_mic_outlined,
                          PhoneMicrophone.peerId,
                          audio.ffiModel.permissions['phone-audio-ready'] ==
                              true,
                          () => PhoneMicrophonePage.showSession(
                              context, PhoneMicrophone.peerId, audio),
                          onClose: () =>
                              unawaited(PhoneMicrophone.disconnect(audio)),
                        ),
                      ),
                    for (final remote in remotes)
                      Obx(() {
                        final host = remote.ffi.ffiModel.pi.hostname.trim();
                        final label = host.isNotEmpty ? host : remote.id;
                        return _sessionChip(
                          Icons.desktop_windows_outlined,
                          label,
                          remote.ffi.ffiModel.pi.isSet.value &&
                              !remote.ffi.ffiModel.waitForFirstImage.value,
                          () => remote.show(context),
                          onClose: () => unawaited(remote.close()),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
      });

  Widget _sessionChip(
    IconData icon,
    String title,
    bool connected,
    VoidCallback onPressed, {
    VoidCallback? onClose,
  }) {
    final status = translate(connected ? 'Connected' : 'Waiting');
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child:
                    Text('$title  ·  $status', overflow: TextOverflow.ellipsis),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: translate('Disconnect'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: const Icon(Icons.close_rounded, size: 15),
                  ),
                ),
              ],
            ],
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class IPhoneDeviceWorkspace extends StatelessWidget {
  const IPhoneDeviceWorkspace(
      {super.key,
      required this.devices,
      required this.onEnterId,
      this.connection});

  final Widget devices;
  final VoidCallback onEnterId;
  final Widget? connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactKeyboard =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
            MediaQuery.viewInsetsOf(context).bottom > 0;
    return SafeArea(
        top: false,
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _ActiveMobileSessions(),
          if (connection != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: connection)
          else if (!compactKeyboard)
            Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 14),
                child: Material(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xff223653)
                        : WorkspaceStyle.navy,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                        onTap: onEnterId,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(translate('New Connection'),
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(color: Colors.white)),
                                    const SizedBox(height: 3),
                                    Text(translate('Enter Remote ID'),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                color:
                                                    const Color(0xffc3d3eb))),
                                  ])),
                              const SizedBox(width: 12),
                              Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                      color: Color(0xff324e76),
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.north_east_rounded,
                                      color: Colors.white, size: 22)),
                            ]))))),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: devices)),
        ]));
  }
}

class _IPhoneConnectionSheet extends StatefulWidget {
  const _IPhoneConnectionSheet({required this.initialId});
  final String initialId;

  @override
  State<_IPhoneConnectionSheet> createState() => _IPhoneConnectionSheetState();
}

class _IPhoneConnectionSheetState extends State<_IPhoneConnectionSheet> {
  final loader = AllPeersLoader();

  @override
  void initState() {
    super.initState();
    loader.init(setState);
    loader.getAllPeers();
  }

  @override
  void dispose() {
    loader.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IPhoneConnectionForm(
        initialId: widget.initialId,
        peers: loader.peers,
        onMatches: loader.queryOnlines,
        onSubmit: (id) => Navigator.pop(context, id),
        onCancel: () => Navigator.pop(context),
      );
}

class IPhoneConnectionForm extends StatefulWidget {
  const IPhoneConnectionForm(
      {super.key,
      required this.initialId,
      required this.peers,
      required this.onMatches,
      required this.onSubmit,
      required this.onCancel});
  final String initialId;
  final List<Peer> peers;
  final ValueChanged<List<Peer>> onMatches;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<IPhoneConnectionForm> createState() => _IPhoneConnectionFormState();
}

class _IPhoneConnectionFormState extends State<IPhoneConnectionForm> {
  late final controller = IDTextEditingController(text: widget.initialId);
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  }

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = controller.id;
    final query = controller.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? const <Peer>[]
        : widget.peers
            .where((peer) =>
                peer.id.toLowerCase().contains(id.toLowerCase()) ||
                peer.alias.toLowerCase().contains(query) ||
                peer.hostname.toLowerCase().contains(query) ||
                peer.username.toLowerCase().contains(query))
            .toList(growable: false);
    widget.onMatches(matches);
    void submit() {
      if (controller.id.isNotEmpty) {
        focus.unfocus();
        widget.onSubmit(controller.id);
      }
    }

    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
            top: false,
            child: CustomScrollView(shrinkWrap: true, slivers: [
              SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                  sliver: SliverToBoxAdapter(
                      child: Row(children: [
                    Expanded(
                        child: Text(translate('New Connection'),
                            style: theme.dialogTheme.titleTextStyle ??
                                theme.textTheme.titleLarge)),
                    IconButton(
                        onPressed: widget.onCancel,
                        tooltip: translate('Close'),
                        icon: const Icon(Icons.close_rounded)),
                  ]))),
              SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  sliver: SliverToBoxAdapter(
                      child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: controller,
                            focusNode: focus,
                            autofocus: true,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.go,
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: [IDTextInputFormatter()],
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => submit(),
                            style: theme.textTheme.titleMedium,
                            decoration: InputDecoration(
                                labelText: translate('Remote ID'),
                                suffixIcon: id.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: translate('Clear'),
                                        icon:
                                            const Icon(Icons.cancel, size: 18),
                                        onPressed: () {
                                          setState(controller.clear);
                                          focus.requestFocus();
                                        })))),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        tooltip: translate('Connect'),
                        onPressed: id.isEmpty ? null : submit,
                        style: IconButton.styleFrom(
                            minimumSize: const Size.square(48),
                            backgroundColor:
                                id.isEmpty ? null : WorkspaceStyle.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13))),
                        icon: const Icon(Icons.arrow_forward_rounded)),
                  ]))),
              if (matches.isNotEmpty)
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    sliver: SliverList.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, i) {
                          final peer = matches[i];
                          final name = peer.alias.isNotEmpty
                              ? peer.alias
                              : peer.hostname;
                          return ListTile(
                              leading: Icon(Icons.devices_rounded,
                                  color: theme.colorScheme.primary),
                              title: Text(
                                  name.isEmpty ? formatID(peer.id) : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  [
                                    if (name.isNotEmpty) formatID(peer.id),
                                    if (peer.platform.isNotEmpty) peer.platform,
                                    translate(
                                        peer.online ? 'Online' : 'Offline')
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.north_west_rounded,
                                  size: 18),
                              onTap: () {
                                setState(() => controller.id = peer.id);
                                focus.unfocus();
                              });
                        })),
            ])));
  }
}
