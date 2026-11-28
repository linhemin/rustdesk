import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';

class WebSettingsPage extends StatelessWidget {
  const WebSettingsPage({Key? key}) : super(key: key);

  static void open(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopSettingPage(initialTabkey: SettingsTabKey.general),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: translate('Settings'),
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => open(context),
    );
  }
}
