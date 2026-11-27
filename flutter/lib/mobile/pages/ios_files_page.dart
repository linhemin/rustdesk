import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/file_model.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import 'file_manager_page.dart';
import 'home_page.dart';

/// Local browsing entry point; remote work uses the existing transfer session.
class IOSFilesPage extends StatefulWidget implements PageShape {
  IOSFilesPage({super.key});

  @override
  final title = translate('files');
  @override
  final icon = const Icon(Icons.folder_outlined);
  @override
  final List<Widget> appBarActions = const [];

  @override
  State<IOSFilesPage> createState() => _IOSFilesPageState();
}

class _IOSFilesPageState extends State<IOSFilesPage> {
  // Local reads do not need a session. Keep their directory independent of gFFI
  // so opening this tab never starts, closes or resets an active connection.
  final _files = FileModel(WeakReference(gFFI));
  final _selection = SelectMode.none.obs;
  final _peersLoader = AllPeersLoader();

  @override
  void initState() {
    super.initState();
    _peersLoader.init(setState);
    _peersLoader.getAllPeers();
    _openHome();
  }

  @override
  void dispose() {
    _peersLoader.clear();
    super.dispose();
  }

  Future<void> _openHome() async {
    final home = await bind.mainGetHomeDir();
    if (!mounted) return;
    _files.localController.homePath = home;
    await _files.localController.openDirectory(home);
  }

  Future<void> _connect() async {
    final lastId = await bind.mainGetLastRemoteId();
    if (!mounted) return;
    if (_peersLoader.needLoad) _peersLoader.getAllPeers();
    var enteredId = trimID(lastId);
    final peers = List<Peer>.from(_peersLoader.peers);
    final peerId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
          builder: (context, update) {
            final query = enteredId.toLowerCase();
            final matches = peers
                .where((peer) =>
                    query.isEmpty ||
                    peer.id.toLowerCase().contains(query) ||
                    peer.alias.toLowerCase().contains(query) ||
                    peer.hostname.toLowerCase().contains(query))
                .take(8)
                .toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 24, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(translate('Transfer file'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    TextFormField(
                        initialValue: formatID(lastId),
                        autofocus: peers.isEmpty,
                        textInputAction: TextInputAction.go,
                        inputFormatters: [IDTextInputFormatter()],
                        decoration: InputDecoration(
                            labelText: translate('Remote ID')),
                        onChanged: (value) =>
                            update(() => enteredId = trimID(value)),
                        onFieldSubmitted: (_) {
                          if (enteredId.isNotEmpty) {
                            Navigator.pop(context, enteredId);
                          }
                        }),
                    if (matches.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: matches.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final peer = matches[index];
                            final title = peer.alias.isNotEmpty
                                ? peer.alias
                                : peer.hostname.isNotEmpty
                                    ? peer.hostname
                                    : formatID(peer.id);
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.devices_rounded,
                                  size: 20),
                              title: Text(title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(formatID(peer.id)),
                              trailing: const Icon(Icons.folder_open_rounded,
                                  size: 18),
                              onTap: () => Navigator.pop(context, peer.id),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                        onPressed: enteredId.isEmpty
                            ? null
                            : () => Navigator.pop(context, enteredId),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: Text(translate('Connect'))),
                  ]),
            );
          }),
    );
    if (mounted && peerId != null) {
      await connect(context, peerId, isFileTransfer: true);
      if (mounted) await _files.localController.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: ColoredBox(
        color: WorkspaceStyle.canvas(context),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(translate('Transfer file'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(translate('Local'),
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor)),
                    ])),
                IconButton(
                    tooltip: translate('Refresh File'),
                    onPressed: _files.localController.refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18)),
                fileManagerSortButton(_files.localController),
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: FileManagerSideSwitcher(
                  showLocal: true,
                  onChanged: (local) {
                    if (!local) _connect();
                  })),
          Expanded(
              child: FileManagerView(
                  controller: _files.localController,
                  selectMode: _selection,
                  sessionActions: false)),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: _connect,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(
                          '${translate("Connect")} · ${translate("Remote")}')))),
        ]),
      ));
}
