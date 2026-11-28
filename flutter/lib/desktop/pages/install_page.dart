import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/brand_links.dart';
import 'package:flutter_hbb/desktop/widgets/install_directory_confirmation.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _InstallPageState() {
    Get.put<DesktopTabController>(tabController);
    const label = "install";
    tabController.add(TabInfo(
        key: label,
        label: label,
        closable: false,
        page: _InstallPageBody(
          key: const ValueKey(label),
        )));
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<DesktopTabController>();
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
      enableResizeEdges: windowManagerEnableResizeEdges,
      child: Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: DesktopTab(controller: tabController)),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  static const _printerStatusTimeout = Duration(seconds: 5);

  late final TextEditingController controller;
  final RxBool startmenu = true.obs;
  final RxBool desktopicon = true.obs;
  final RxBool printer = false.obs;
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;
  final RxBool cancelEnabled = true.obs;

  _InstallPageBodyState() {
    controller = TextEditingController(text: bind.installInstallPath());
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu.value = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon.value = installOptions['DESKTOPSHORTCUTS'] != '0';
    printer.value = installOptions['PRINTER'] == '1';
  }

  Future<void> _loadPrinterStatus() async {
    btnEnabled.value = false;
    showProgress.value = true;
    try {
      final status = await bind
          .mainGetCommon(key: 'is-printer-installed')
          .timeout(_printerStatusTimeout);
      printer.value = status == 'true';
      if (status != 'true' && status != 'false') {
        debugPrint('Failed to check printer installation status: $status');
      }
    } catch (e) {
      printer.value = false;
      debugPrint('Failed to check printer installation status: $e');
    } finally {
      showProgress.value = false;
      btnEnabled.value = true;
    }
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
    if (printer.value) {
      _loadPrinterStatus();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  InkWell Option(RxBool option, {String label = ''}) {
    return InkWell(
      // todo mouseCursor: "SystemMouseCursors.forbidden" or no cursor on btnEnabled == false
      borderRadius: BorderRadius.circular(6),
      onTap: () => btnEnabled.value ? option.value = !option.value : null,
      child: Row(
        children: [
          Obx(
            () => Checkbox(
              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
              value: option.value,
              onChanged: (v) =>
                  btnEnabled.value ? option.value = !option.value : null,
            ).marginOnly(right: 8),
          ),
          Expanded(
            child: Text(translate(label)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double em = 13;
    return Scaffold(
      body: Column(children: [
        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(translate('Installation'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              readOnly: true,
              decoration: InputDecoration(
                  labelText: translate('Installation Path'),
                  suffixIcon: Obx(() => IconButton(
                      tooltip: translate('Change Path'),
                      onPressed: btnEnabled.value ? selectInstallPath : null,
                      icon: const Icon(Icons.folder_open_outlined)))),
            ).workaroundFreezeLinuxMint(),
            ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) =>
                    InstallDirectoryWarning(directoryPath: value.text)),
            const SizedBox(height: 18),
            Option(startmenu, label: 'Create start menu shortcuts')
                .marginOnly(bottom: 7),
            Option(desktopicon, label: 'Create desktop icon')
                .marginOnly(bottom: 7),
            Option(printer, label: 'Install {$appName} Printer'),
            Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 32)
                        .marginOnly(right: 16),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(translate('agreement_tip')).marginOnly(bottom: em),
                        InkWell(
                          hoverColor: Colors.transparent,
                          onTap: () => launchUrlString(BrandLinks.privacyUrl),
                          child: Tooltip(
                            message: BrandLinks.privacyUrl,
                            child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Icon(Icons.launch_outlined, size: 16)
                                      .marginOnly(right: 5),
                                  Text(
                                    translate('End-user license agreement'),
                                    style: const TextStyle(
                                        decoration: TextDecoration.underline),
                                  )
                                ]),
                          ),
                        ),
                      ],
                    ))
                  ],
                )).marginSymmetric(vertical: 2 * em),
          ]),
        )),
        Obx(() => showProgress.value
            ? const LinearProgressIndicator(minHeight: 2)
            : const Divider(height: 1)),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      if (!bind.installShowRunWithoutInstall())
                        Obx(() => TextButton(
                            onPressed: btnEnabled.value
                                ? () => bind.installRunWithoutInstall()
                                : null,
                            child: Text(translate('Run without install')))),
                      Obx(() => OutlinedButton(
                          onPressed: cancelEnabled.value
                              ? () => windowManager.close()
                              : null,
                          child: Text(translate('Cancel')))),
                      Obx(() => ElevatedButton.icon(
                          onPressed: btnEnabled.value ? install : null,
                          icon: const Icon(Icons.done_rounded, size: 16),
                          label: Text(translate('Accept and Install')))),
                    ]))),
      ]),
    );
  }

  Future<void> install() async {
    if (!btnEnabled.value) return;
    final installPath = controller.text;
    do_install() {
      btnEnabled.value = false;
      cancelEnabled.value = false;
      showProgress.value = true;
      String args = '';
      if (startmenu.value) args += ' startmenu';
      if (desktopicon.value) args += ' desktopicon';
      if (printer.value) args += ' printer';
      bind.installInstallMe(options: args, path: installPath);
    }

    btnEnabled.value = false;
    try {
      final confirmed =
          await confirmInstallDirectory(this.context, targetPath: installPath);
      if (!mounted || !confirmed) return;
      do_install();
    } finally {
      if (mounted && !showProgress.value) btnEnabled.value = true;
    }
  }

  void selectInstallPath() async {
    String? install_path = await FilePicker.platform
        .getDirectoryPath(initialDirectory: controller.text);
    if (install_path != null) {
      controller.text = join(install_path, await bind.mainGetAppName());
    }
  }
}
