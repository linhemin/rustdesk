import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/peer_tab_model.dart';
import 'login.dart';
import 'peer_card.dart';
import 'peers_view.dart';

class OwnedDevices extends StatelessWidget {
  const OwnedDevices({super.key, this.menuPadding});

  final EdgeInsets? menuPadding;

  @override
  Widget build(BuildContext context) {
    final user = gFFI.userModel;
    final devices = user.ownedDevices;
    return Obx(() {
      if (!user.isLogin) {
        return Center(
          child: FilledButton.icon(
            onPressed: loginDialog,
            icon: const Icon(Icons.login_rounded),
            label: Text(translate('Login')),
          ),
        );
      }
      if (user.networkError.isNotEmpty) return netWorkErrorWidget();
      if (devices.loading.value && devices.peers.peers.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final error = devices.loadError.value;
      return Column(
        children: [
          if (error.isNotEmpty)
            Container(
              color: MyTheme.color(context).errorBannerBg,
              child: ListTile(
                dense: true,
                title: Text(translate(error)),
                trailing: TextButton(
                  onPressed: () => user.refreshOwnedDevices(force: true),
                  child: Text(translate('Retry')),
                ),
              ),
            ),
          Expanded(child: _OwnedPeers(menuPadding: menuPadding)),
        ],
      );
    });
  }
}

class _OwnedPeers extends BasePeersView {
  _OwnedPeers({EdgeInsets? menuPadding})
      : super(
          peerTabIndex: PeerTabIndex.owned,
          peerCardBuilder: (peer) => MyGroupPeerCard(
            peer: peer,
            tab: PeerTabIndex.owned,
            menuPadding: menuPadding,
          ),
        );
}
