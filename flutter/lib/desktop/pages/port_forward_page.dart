import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

class _PortForward {
  int localPort;
  String remoteHost;
  int remotePort;

  _PortForward.fromJson(List<dynamic> json)
      : localPort = json[0] as int,
        remoteHost = json[1] as String,
        remotePort = json[2] as int;
}

class PortForwardPage extends StatefulWidget {
  PortForwardPage({
    Key? key,
    required this.id,
    required this.password,
    this.loginMethod = '',
    required this.tabController,
    required this.isRDP,
    required this.isSharedPassword,
    this.forceRelay,
    this.connToken,
  }) : super(key: key);
  final String id;
  final String? password;
  final String loginMethod;
  final DesktopTabController tabController;
  final bool isRDP;
  final bool? forceRelay;
  final bool? isSharedPassword;
  final String? connToken;
  final SimpleWrapper<State<PortForwardPage>?> _lastState = SimpleWrapper(null);

  FFI get ffi => (_lastState.value! as _PortForwardPageState)._ffi;

  @override
  State<PortForwardPage> createState() {
    final state = _PortForwardPageState();
    _lastState.value = state;
    return state;
  }
}

class _PortForwardPageState extends State<PortForwardPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController localPortController = TextEditingController();
  final TextEditingController remoteHostController = TextEditingController();
  final TextEditingController remotePortController = TextEditingController();
  RxList<_PortForward> pfs = RxList.empty(growable: true);
  late FFI _ffi;

  @override
  void initState() {
    super.initState();
    _ffi = FFI(null);
    _ffi.start(widget.id,
        isPortForward: true,
        password: widget.password,
        loginMethod: widget.loginMethod,
        isSharedPassword: widget.isSharedPassword,
        forceRelay: widget.forceRelay,
        connToken: widget.connToken,
        isRdp: widget.isRDP);
    Get.put<FFI>(_ffi, tag: 'pf_${widget.id}');
    debugPrint("Port forward page init success with id ${widget.id}");
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tabController.onSelected?.call(widget.id);
    });
  }

  @override
  void dispose() {
    _ffi.close();
    _ffi.dialogManager.dismissAll();
    Get.delete<FFI>(tag: 'pf_${widget.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FutureBuilder(future: () async {
        if (!widget.isRDP) {
          refreshTunnelConfig();
        }
      }(), builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildPrompt(context),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Theme.of(context).dividerColor)),
                    child:
                        widget.isRDP ? buildRdp(context) : buildTunnel(context),
                  ),
                ),
              ],
            ),
          );
        }
        return const Offstage();
      }),
    );
  }

  buildPrompt(BuildContext context) {
    return Obx(() => Offstage(
          offstage: pfs.isEmpty && !widget.isRDP,
          child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: WorkspaceStyle.navy,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      translate('Listening ...'),
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    Text(
                      translate('not_close_tcp_tip'),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFDDDDDD), height: 1.2),
                    )
                  ])).marginOnly(bottom: 8),
        ));
  }

  Widget buildTunnel(BuildContext context) => Obx(() => ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: pfs.length + 1,
        itemBuilder: (context, index) => index == 0
            ? buildTunnelAddRow(context)
            : buildTunnelDataRow(context, pfs[index - 1]),
      ));

  Widget buildTunnelAddRow(BuildContext context) {
    var portInputFormatter = [
      FilteringTextInputFormatter.allow(RegExp(
          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'))
    ];

    Widget field(String label, TextEditingController controller,
            {bool port = false}) =>
        TextField(
          controller: controller,
          inputFormatters: port ? portInputFormatter : null,
          decoration: InputDecoration(
              labelText: translate(label), hintText: port ? null : 'localhost'),
        ).workaroundFreezeLinuxMint();
    final add = ElevatedButton.icon(
      onPressed: () async {
        int? localPort = int.tryParse(localPortController.text);
        int? remotePort = int.tryParse(remotePortController.text);
        if (localPort != null &&
            remotePort != null &&
            (remoteHostController.text.isEmpty ||
                remoteHostController.text.trim().isNotEmpty)) {
          await bind.sessionAddPortForward(
              sessionId: _ffi.sessionId,
              localPort: localPort,
              remoteHost: remoteHostController.text.trim().isEmpty
                  ? 'localhost'
                  : remoteHostController.text.trim(),
              remotePort: remotePort);
          localPortController.clear();
          remoteHostController.clear();
          remotePortController.clear();
          refreshTunnelConfig();
        }
      },
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(translate('Add')),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(translate('TCP tunneling'),
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, bounds) {
        final local = field('Local Port', localPortController, port: true);
        final host = field('Remote Host', remoteHostController);
        final remote = field('Remote Port', remotePortController, port: true);
        if (bounds.maxWidth < 540) {
          return Column(children: [
            local,
            const SizedBox(height: 10),
            host,
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: remote),
              const SizedBox(width: 10),
              add
            ]),
          ]);
        }
        return Row(children: [
          Expanded(child: local),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, size: 18)),
          Expanded(flex: 2, child: host),
          const SizedBox(width: 8),
          Expanded(child: remote),
          const SizedBox(width: 10),
          add,
        ]);
      }),
      if (pfs.isNotEmpty) const Divider(height: 30),
    ]);
  }

  Widget buildTunnelDataRow(BuildContext context, _PortForward pf) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.route_outlined),
      title: Text('${pf.remoteHost}:${pf.remotePort}'),
      subtitle: Text('${translate("Local Port")}  ${pf.localPort}'),
      trailing: IconButton(
          tooltip: translate('Remove'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () async {
            await bind.sessionRemovePortForward(
                sessionId: _ffi.sessionId, localPort: pf.localPort);
            refreshTunnelConfig();
          }),
    );
  }

  void refreshTunnelConfig() async {
    String peer = bind.mainGetPeerSync(id: widget.id);
    Map<String, dynamic> config = jsonDecode(peer);
    List<dynamic> infos = config['port_forwards'] as List;
    List<_PortForward> result = List.empty(growable: true);
    for (var e in infos) {
      result.add(_PortForward.fromJson(e));
    }
    pfs.value = result;
  }

  Widget buildRdp(BuildContext context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(18),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.desktop_windows_outlined),
            title:
                Text(widget.id, style: Theme.of(context).textTheme.titleMedium),
            subtitle: const Text('RDP'),
          ),
          Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton.icon(
                onPressed: () => bind.sessionNewRdp(sessionId: _ffi.sessionId),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(translate('New RDP')),
              )),
        ],
      );

  @override
  bool get wantKeepAlive => true;
}
