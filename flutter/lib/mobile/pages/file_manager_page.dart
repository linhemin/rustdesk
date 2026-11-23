import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:get/get.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../utils/android_documents.dart';
import '../widgets/file_transfer_widgets.dart';

class FileManagerPage extends StatefulWidget {
  FileManagerPage(
      {Key? key,
      required this.id,
      this.loginMethod = '',
      this.password,
      this.isSharedPassword,
      this.forceRelay})
      : super(key: key);
  final String id;
  final String loginMethod;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;

  @override
  State<StatefulWidget> createState() => _FileManagerPageState();
}

enum SelectMode { local, remote, none }

extension SelectModeEq on SelectMode {
  bool eq(bool? currentIsLocal) {
    if (currentIsLocal == null) {
      return false;
    }
    if (currentIsLocal) {
      return this == SelectMode.local;
    } else {
      return this == SelectMode.remote;
    }
  }
}

extension SelectModeExt on Rx<SelectMode> {
  void toggle(bool currentIsLocal) {
    switch (value) {
      case SelectMode.local:
        value = SelectMode.none;
        break;
      case SelectMode.remote:
        value = SelectMode.none;
        break;
      case SelectMode.none:
        if (currentIsLocal) {
          value = SelectMode.local;
        } else {
          value = SelectMode.remote;
        }
        break;
    }
  }
}

class _FileManagerPageState extends State<FileManagerPage> {
  final model = gFFI.fileModel;
  final selectMode = SelectMode.none.obs;

  var showLocal = true;
  bool _showTransferQueue = false;

  FileController get currentFileController =>
      showLocal ? model.localController : model.remoteController;
  FileDirectory get currentDir => currentFileController.directory.value;
  DirectoryOptions get currentOptions => currentFileController.options.value;
  final _uniqueKey = UniqueKey();

  Future<T> _runAndroidDocumentPicker<T>(Future<T> Function() action) async {
    gFFI.ffiModel.beginAndroidDocumentPicker();
    try {
      return await action();
    } finally {
      gFFI.ffiModel.endAndroidDocumentPicker();
    }
  }

  Future<void> _importFiles() async {
    var imported = 0;
    var failed = false;
    final importController = currentFileController;
    final importDirectory = currentDir.path;
    final importIsWindows = currentOptions.isWindows;
    try {
      final selectedFiles = await _runAndroidDocumentPicker(() =>
          gFFI.invokeMethodWithResult<List<dynamic>>(
              AndroidChannel.kPickImportFiles));
      if (selectedFiles == null || selectedFiles.isEmpty) return;

      for (final selected in selectedFiles) {
        final uri = (selected as Map<dynamic, dynamic>)['uri'] as String?;
        final selectedName = selected['name'] as String?;
        final name = selectedName?.replaceAll('\\', '/').split('/').last;
        if (uri == null ||
            name == null ||
            !PathUtil.validName(name, importIsWindows)) {
          failed = true;
          continue;
        }
        final destination =
          PathUtil.join(importDirectory, name, importIsWindows);
        var overwrite = false;
        if (await File(destination).exists()) {
          final overwriteResult = await model.showFileConfirmDialog(
              translate('Overwrite'), destination, false, false);
          if (overwriteResult == false) break;
          if (overwriteResult != true) continue;
          overwrite = true;
        }
        try {
          final success = await gFFI.invokeMethod(
              AndroidChannel.kImportFile,
              {'uri': uri, 'path': destination, 'overwrite': overwrite});
          if (success == true) {
            imported++;
          } else {
            failed = true;
          }
        } catch (e) {
          failed = true;
          debugPrint('Failed to import $name: $e');
        }
      }
    } catch (e) {
      failed = true;
      debugPrint('Failed to select files for import: $e');
    }
    await importController.refresh();
    if (failed) {
      showToast(translate('Failed'));
    } else if (imported > 0) {
      showToast(translate('Successful'));
    }
  }

  Future<void> _changeLocalStorage({required bool workspace}) async {
    try {
      final path = workspace
          ? await AndroidDocuments.workspace()
          : (await AndroidDocuments.selectFolder())?['path'] as String?;
      if (path == null || !mounted) return;
      final previousHome = model.localController.homePath;
      model.localController.homePath = path;
      try {
        if (await model.localController.openDirectory(path, isBack: true)) {
          model.localController.history.clear();
        } else {
          model.localController.homePath = previousHome;
        }
      } catch (_) {
        model.localController.homePath = previousHome;
        rethrow;
      }
    } catch (error) {
      showToast(error.toString());
    }
  }

  Future<void> _exportFile(Entry entry) async {
    try {
      final exported = await _runAndroidDocumentPicker(() => gFFI
          .invokeMethod(AndroidChannel.kExportFile, {'path': entry.path}));
      if (exported == true) {
        showToast(translate('Successful'));
      }
    } catch (e) {
      debugPrint('Failed to export ${entry.name}: $e');
      showToast(translate('Failed'));
    }
  }

  Future<void> _importFolder() async {
    final importController = currentFileController;
    final importDirectory = currentDir.path;
    final importIsWindows = currentOptions.isWindows;
    try {
      final picked = await _runAndroidDocumentPicker(() =>
          gFFI.invokeMethodWithResult<Map<dynamic, dynamic>>(
              AndroidChannel.kPickImportDirectory));
      if (picked == null || picked.isEmpty) return;
      final uri = picked['uri'] as String?;
      final name =
          (picked['name'] as String?)?.replaceAll('\\', '/').split('/').last;
      if (uri == null ||
          name == null ||
          name == '.' ||
          name == '..' ||
          !PathUtil.validName(name, importIsWindows)) {
        showToast(translate('Failed'));
        return;
      }
      final destination = PathUtil.join(importDirectory, name, importIsWindows);
      final destinationType = await FileSystemEntity.type(destination);
      var overwrite = false;
      if (destinationType == FileSystemEntityType.directory) {
        final overwriteResult = await model.showFileConfirmDialog(
            translate('Overwrite'), destination, false, false);
        if (overwriteResult != true) return;
        overwrite = true;
      } else if (destinationType != FileSystemEntityType.notFound) {
        showToast(translate('Failed'));
        return;
      }
      final success = await gFFI.invokeMethod(AndroidChannel.kImportDirectory,
          {'uri': uri, 'path': destination, 'overwrite': overwrite});
      if (success == true) {
        showToast(translate('Successful'));
      } else {
        showToast(translate('Failed'));
      }
    } catch (e) {
      debugPrint('Failed to import folder: $e');
      showToast(translate('Failed'));
    }
    await importController.refresh();
  }

  Future<void> _exportItems(SelectedItems items) async {
    await _exportPaths(items.items.map((e) => e.path));
  }

  Future<void> _exportLogs() async {
    final String home;
    try {
      home = await AndroidDocuments.workspace();
    } catch (error) {
      showToast(error.toString());
      return;
    }
    final appDir = PathUtil.join(home, appName, false);
    final paths = [
      PathUtil.join(appDir, 'Logs', false),
      PathUtil.join(appDir, 'ScreenRecord', false),
    ].where((p) => File(p).existsSync() || Directory(p).existsSync()).toList();
    await _exportPaths(paths, includeDocumentLogs: true);
  }

  Future<void> _exportPaths(Iterable<String> paths,
      {bool includeDocumentLogs = false}) async {
    try {
      final result = await _runAndroidDocumentPicker(() => gFFI
              .invokeMethodWithResult<Map<dynamic, dynamic>>(
                  AndroidChannel.kExportFiles, {
            'paths': paths.toList(),
            if (includeDocumentLogs) 'documentLogs': true,
          }));
      if (result == null) return;
      final exported = result['exported'] as int? ?? 0;
      final failed = result['failed'] as int? ?? 0;
      if (includeDocumentLogs && exported > 0 && failed > 0) {
        showToast('${translate('Successful')}: $exported, '
            '${translate('Failed')}: $failed');
      } else if (failed > 0 || (includeDocumentLogs && exported == 0)) {
        showToast(translate('Failed'));
      } else if (exported > 0) {
        showToast(translate('Successful'));
      }
    } catch (e) {
      debugPrint('Failed to export paths: $e');
      showToast(translate('Failed'));
    }
  }

  void _createFolder() {
    final name = TextEditingController();
    String? errorText;
    gFFI.dialogManager.show((setState, close, context) {
      name.addListener(() {
        if (errorText != null) {
          setState(() {
            errorText = null;
          });
        }
      });
      return CustomAlertDialog(
          title: Text(translate("Create Folder")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: InputDecoration(
                  labelText: translate("Please enter the folder name"),
                  errorText: errorText,
                ),
                controller: name,
              ).workaroundFreezeLinuxMint(),
            ],
          ),
          actions: [
            dialogButton("Cancel",
                onPressed: () => close(false), isOutline: true),
            dialogButton("OK", onPressed: () {
              if (name.value.text.isNotEmpty) {
                if (!PathUtil.validName(name.value.text,
                    currentFileController.options.value.isWindows)) {
                  setState(() {
                    errorText = translate("Invalid folder name");
                  });
                  return;
                }
                currentFileController.createDir(PathUtil.join(currentDir.path,
                    name.value.text, currentOptions.isWindows));
                close();
              }
            })
          ]);
    });
  }

  Widget _headerTitle() => AnimatedBuilder(
        animation: gFFI.ffiModel,
        builder: (context, _) => Obx(() {
          final active = model.jobController.jobTable
              .firstWhereOrNull((job) => job.state == JobState.inProgress);
          final direct = gFFI.ffiModel.direct;
          final link = direct == null
              ? translate('Connecting...')
              : direct
                  ? 'P2P'
                  : translate('Relay Connection');
          final peer = gFFI.ffiModel.pi.hostname;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                      child: Text(translate('Transfer file'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: WorkspaceStyle.success(context)
                                  .withOpacity(.12),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(
                              '$link${active != null && active.speed > 0 ? " · ${readableFileSize(active.speed)}/s" : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 9,
                                  color: WorkspaceStyle.success(context),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])))),
                ]),
                const SizedBox(height: 3),
                Text(
                    '${translate(direct == null ? "Connecting..." : "Connected")}: ${peer.isEmpty ? widget.id : peer}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).hintColor)),
              ]);
        }),
      );

  @override
  void initState() {
    super.initState();
    gFFI.start(widget.id,
        isFileTransfer: true,
        loginMethod: widget.loginMethod,
        password: widget.password,
        isSharedPassword: widget.isSharedPassword,
        forceRelay: widget.forceRelay);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, widget.id);
    WakelockManager.enable(_uniqueKey);
  }

  @override
  void dispose() {
    model.close().whenComplete(() {
      gFFI.close();
      gFFI.dialogManager.dismissAll();
      WakelockManager.disable(_uniqueKey);
    });
    model.jobController.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
      onWillPop: () async {
        if (selectMode.value != SelectMode.none) {
          selectMode.value = SelectMode.none;
          setState(() {});
        } else {
          currentFileController.goBack();
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: WorkspaceStyle.canvas(context),
        appBar: AppBar(
          backgroundColor: WorkspaceStyle.canvas(context),
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          centerTitle: false,
          title: _headerTitle(),
          actions: [
            Obx(() => IconButton(
                  tooltip: translate('Create Folder'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  onPressed:
                      currentDir.path.isNotEmpty && currentDir.path != '/'
                          ? _createFolder
                          : null,
                )),
            fileManagerSortButton(currentFileController),
            PopupMenuButton<String>(
                tooltip: "",
                icon: const Icon(Icons.more_horiz_rounded),
                itemBuilder: (context) {
                  return [
                    PopupMenuItem(
                        value: 'close', child: Text(translate('Close'))),
                    if (isAndroid && showLocal) ...[
                      PopupMenuItem(
                        value: 'workspace',
                        child: Row(
                          children: [
                            Icon(Icons.storage_outlined,
                                color: Theme.of(context).iconTheme.color),
                            SizedBox(width: 5),
                            Text(translate('RustDesk storage')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'choose_folder',
                        child: Row(
                          children: [
                            Icon(Icons.folder_open_outlined,
                                color: Theme.of(context).iconTheme.color),
                            SizedBox(width: 5),
                            Text('${translate('Other folders')}…'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                    ],
                    PopupMenuItem(
                      child: Row(
                        children: [
                          Icon(Icons.refresh,
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Refresh File"))
                        ],
                      ),
                      value: "refresh",
                    ),
                    if (isAndroid && !AndroidDocuments.isPath(currentDir.path))
                      PopupMenuItem(
                        enabled: showLocal && currentDir.path.isNotEmpty,
                        value: "import",
                        child: Row(
                          children: [
                            Icon(Icons.add_to_drive,
                                color: Theme.of(context).iconTheme.color),
                            SizedBox(width: 5),
                            Text(translate("Add"))
                          ],
                        ),
                      ),
                    if (isAndroid && !AndroidDocuments.isPath(currentDir.path))
                      PopupMenuItem(
                        enabled: showLocal && currentDir.path.isNotEmpty,
                        value: "import_folder",
                        child: Row(
                          children: [
                            Icon(Icons.create_new_folder_outlined,
                                color: Theme.of(context).iconTheme.color),
                            SizedBox(width: 5),
                            Text(translate("Import Folder"))
                          ],
                        ),
                      ),
                    if (isAndroid)
                      PopupMenuItem(
                        enabled: showLocal && currentDir.path.isNotEmpty,
                        value: "export_logs",
                        child: Row(
                          children: [
                            Icon(Icons.article_outlined,
                                color: Theme.of(context).iconTheme.color),
                            SizedBox(width: 5),
                            Text(translate("Export Logs"))
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(Icons.check,
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Multi Select"))
                        ],
                      ),
                      value: "select",
                    ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(Icons.folder_outlined,
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Create Folder"))
                        ],
                      ),
                      value: "folder",
                    ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(
                              currentOptions.showHidden
                                  ? Icons.check_box_outlined
                                  : Icons.check_box_outline_blank,
                              color: Theme.of(context).iconTheme.color),
                          SizedBox(width: 5),
                          Text(translate("Show Hidden Files"))
                        ],
                      ),
                      value: "hidden",
                    )
                  ];
                },
                onSelected: (v) {
                  if (v == 'close') {
                    clientClose(gFFI.sessionId, gFFI);
                  } else if (v == 'workspace' || v == 'choose_folder') {
                    _changeLocalStorage(workspace: v == 'workspace');
                  } else if (v == "refresh") {
                    currentFileController.refresh();
                  } else if (v == "import") {
                    _importFiles();
                  } else if (v == "import_folder") {
                    _importFolder();
                  } else if (v == "export_logs") {
                    _exportLogs();
                  } else if (v == "select") {
                    model.localController.selectedItems.clear();
                    model.remoteController.selectedItems.clear();
                    selectMode.toggle(showLocal);
                    setState(() {});
                  } else if (v == "folder") {
                    _createFolder();
                  } else if (v == "hidden") {
                    currentFileController.toggleShowHidden();
                  }
                }),
          ],
        ),
        body: Column(children: [
          Expanded(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: FileManagerSideSwitcher(
                remoteName: gFFI.ffiModel.pi.platform,
                showLocal: showLocal,
                onChanged: (local) {
                  if (local != showLocal) setState(() => showLocal = local);
                },
              ),
            ),
            Expanded(
                child: showLocal
                    ? FileManagerView(
                        controller: model.localController,
                        selectMode: selectMode,
                      )
                    : FileManagerView(
                        controller: model.remoteController,
                        selectMode: selectMode,
                      )),
          ])),
          bottomSheet(),
        ]),
      ));

  Widget bottomSheet() => Obx(() {
        final jobs = model.jobController.jobTable;
        final selected = getActiveSelectedItems();
        final active = jobs
                .firstWhereOrNull((job) => job.state == JobState.inProgress) ??
            jobs.firstWhereOrNull((job) =>
                job.state == JobState.none || job.state == JobState.paused) ??
            jobs.lastOrNull;
        final theme = Theme.of(context);
        final progressing = active?.state == JobState.inProgress;
        final detail = active == null
            ? ''
            : progressing
                ? '${active.percentText} · ${readableFileSize(active.speed)}/s'
                : active.getStatus();
        return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (selectMode.value != SelectMode.none)
                  _selectionBar(selected),
                if (_showTransferQueue)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: theme.cardColor,
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                '${translate("Transfer file")} · ${jobs.length}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600))),
                        if (active != null)
                          IconButton(
                              tooltip:
                                  translate(progressing ? 'Cancel' : 'Close'),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () {
                                if (progressing) {
                                  model.jobController.cancelJob(active.id);
                                }
                                jobs.clear();
                              }),
                      ]),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * .25),
                        child: jobs.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(translate('Empty'),
                                    style: TextStyle(color: theme.hintColor)))
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: jobs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final job = jobs[index];
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: WorkspaceStyle.elevatedSurface(
                                            context),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              job.fileName.isEmpty
                                                  ? job.jobName
                                                  : job.fileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                  value: job.percent
                                                      .clamp(0.0, 1.0),
                                                  minHeight: 5,
                                                  backgroundColor:
                                                      theme.dividerColor)),
                                          const SizedBox(height: 6),
                                          Text(
                                              '${job.getStatus()} · ${job.percentText}'
                                              '${job.state == JobState.inProgress ? " · ${readableFileSize(job.speed)}/s" : ""}',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: theme.hintColor,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures()
                                                  ])),
                                        ]),
                                  );
                                }),
                      ),
                    ]),
                  ),
                MobileTransferPill(
                  label: '${translate("Transfer file")} · ${jobs.length}',
                  detail: detail,
                  active: progressing,
                  expanded: _showTransferQueue,
                  onToggle: () =>
                      setState(() => _showTransferQueue = !_showTransferQueue),
                ),
              ]),
            ));
      });

  Widget _selectionBar(SelectedItems? selected) {
    final theme = Theme.of(context);
    final source = selected?.isLocal == false
        ? model.remoteController
        : model.localController;
    final target = selected?.isLocal == false
        ? model.localController
        : model.remoteController;
    final count = selected?.items.length ?? 0;
    final size =
        selected?.items.fold<int>(0, (sum, entry) => sum + entry.size) ?? 0;
    void clear() {
      selected?.clear();
      selectMode.value = SelectMode.none;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
      decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: Text(
                  '${translate("Selected")} $count · ${readableFileSize(size.toDouble())}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600))),
          PopupMenuButton<String>(
            tooltip: translate('More'),
            icon: const Icon(Icons.more_horiz_rounded, size: 18),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'switch',
                  child: Text(translate(showLocal ? 'Remote' : 'Local'))),
              PopupMenuItem(
                  value: 'delete',
                  enabled: count > 0,
                  child: Text(translate('Delete'))),
              if (count == 1 &&
                  versionCmp(gFFI.ffiModel.pi.version, '1.3.0') >= 0)
                PopupMenuItem(
                    value: 'rename', child: Text(translate('Rename'))),
              if (isAndroid &&
                  selectMode.value.eq(showLocal) &&
                  !AndroidDocuments.isPath(currentDir.path) &&
                  selected?.isLocal == true &&
                  count > 0)
                PopupMenuItem(
                    value: 'export',
                    child: Text(translate(
                        count == 1 && selected!.items.single.isFile
                            ? 'Save as'
                            : 'Export'))),
            ],
            onSelected: (action) async {
              if (action == 'switch') {
                setState(() => showLocal = !showLocal);
              } else if (action == 'delete' && selected != null) {
                await source.removeAction(selected);
                clear();
              } else if (action == 'rename' && selected != null) {
                await source.renameAction(
                    selected.items.single, selected.isLocal);
                clear();
              } else if (action == 'export' && selected != null) {
                if (count == 1 && selected.items.single.isFile) {
                  await _exportFile(selected.items.single);
                } else {
                  await _exportItems(selected);
                }
              }
            },
          ),
        ]),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: clear,
                  child: Text(translate('Cancel'),
                      maxLines: 1, overflow: TextOverflow.ellipsis))),
          const SizedBox(width: 8),
          Expanded(
              child: FilledButton(
            onPressed: selected == null ||
                    count == 0 ||
                    target.directory.value.path.isEmpty
                ? null
                : () {
                    final destination = selectMode.value.eq(showLocal)
                        ? target.directoryData()
                        : DirectoryData(currentDir, currentOptions);
                    source.sendFiles(selected, destination);
                    clear();
                  },
            child: Text(
                selectMode.value.eq(showLocal)
                    ? '${translate(selected?.isLocal == false ? "Receive" : "Send")} → ${translate(selected?.isLocal == false ? "Local" : "Remote")}'
                    : translate('Paste here?'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          )),
        ]),
      ]),
    );
  }

  SelectedItems? getActiveSelectedItems() {
    final localSelectedItems = model.localController.selectedItems;
    final remoteSelectedItems = model.remoteController.selectedItems;

    if (localSelectedItems.items.isNotEmpty &&
        remoteSelectedItems.items.isNotEmpty) {
      // assert unreachable
      debugPrint("Wrong SelectedItems state, reset");
      localSelectedItems.clear();
      remoteSelectedItems.clear();
    }

    if (localSelectedItems.items.isEmpty && remoteSelectedItems.items.isEmpty) {
      return null;
    }

    if (localSelectedItems.items.length > remoteSelectedItems.items.length) {
      return localSelectedItems;
    } else {
      return remoteSelectedItems;
    }
  }
}

class FileManagerView extends StatefulWidget {
  final FileController controller;
  final Rx<SelectMode> selectMode;

  FileManagerView(
      {required this.controller,
      required this.selectMode,
      this.sessionActions = true});
  final bool sessionActions;

  @override
  State<StatefulWidget> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  final _listScrollController = ScrollController();
  final _breadCrumbScroller = ScrollController();

  bool get isLocal => widget.controller.isLocal;
  FileController get controller => widget.controller;
  SelectedItems get _selectedItems => widget.controller.selectedItems;

  @override
  void initState() {
    super.initState();
    controller.directory.listen((e) => breadCrumbScrollToEnd());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      headTools(),
      Expanded(child: Obx(() {
        final entries = controller.directory.value.entries;
        final mode = widget.selectMode.value;
        final selectedEntries = _selectedItems.items.toSet();
        if (entries.isEmpty) {
          return ListView(children: [
            const SizedBox(height: 72),
            Icon(Icons.folder_open_outlined,
                size: 32, color: Theme.of(context).hintColor),
            const SizedBox(height: 8),
            Center(
                child: Text(translate('Empty'),
                    style: TextStyle(color: Theme.of(context).hintColor))),
            listTail(),
          ]);
        }
        return ListView.builder(
          controller: _listScrollController,
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index >= entries.length) {
              return listTail();
            }
            final selected = mode != SelectMode.none &&
                selectedEntries.contains(entries[index]);

            final sizeStr = entries[index].isFile
                ? readableFileSize(entries[index].size.toDouble())
                : "";

            final showCheckBox = mode.eq(isLocal);
            final theme = Theme.of(context);
            final primary = theme.colorScheme.primary;
            final entry = entries[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Material(
                color: selected ? primary.withOpacity(0.11) : theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: selected
                        ? primary.withOpacity(0.45)
                        : theme.dividerColor,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                  horizontalTitleGap: 12,
                  leading: MobileFileIcon(
                      name: entry.name,
                      directory: entry.isDirectory,
                      drive: entry.isDrive),
                  title: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  selected: selected,
                  subtitle: entry.isDrive
                      ? null
                      : Text(
                          "${sizeStr.isEmpty ? '' : '$sizeStr · '}${entry.lastModified().toString().substring(0, 16)}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.hintColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                  trailing:
                      entry.isDrive || (entry.isDirectory && !showCheckBox)
                          ? Icon(Icons.chevron_right_rounded,
                              size: 18, color: theme.hintColor)
                          : widget.sessionActions
                              ? Checkbox(
                                  shape: const CircleBorder(),
                                  value: selected,
                                  onChanged: (v) {
                                    if (v == null) return;
                                    if (!showCheckBox) {
                                      if (widget.selectMode.value !=
                                          SelectMode.none) return;
                                      _selectedItems.clear();
                                      widget.selectMode.toggle(isLocal);
                                    }
                                    if (v && !selected) {
                                      _selectedItems.add(entry);
                                    } else if (!v && selected) {
                                      _selectedItems.remove(entry);
                                    }
                                    setState(() {});
                                  })
                              : null,
                  onTap: !widget.sessionActions && entry.isFile ? null : () {
                    if (showCheckBox) {
                      if (selected) {
                        _selectedItems.remove(entry);
                      } else {
                        _selectedItems.add(entry);
                      }
                      setState(() {});
                      return;
                    }
                    if (entry.isDirectory || entry.isDrive) {
                      controller.openDirectory(entry.path);
                    } else if (widget.selectMode.value == SelectMode.none) {
                      _selectedItems.clear();
                      widget.selectMode.toggle(isLocal);
                      _selectedItems.add(entry);
                      setState(() {});
                    }
                  },
                  onLongPress: entry.isDrive || !widget.sessionActions
                      ? null
                      : () {
                          _selectedItems.clear();
                          widget.selectMode.toggle(isLocal);
                          if (widget.selectMode.value != SelectMode.none) {
                            _selectedItems.add(entry);
                          }
                          setState(() {});
                        },
                ),
              ),
            );
          },
        );
      }))
    ]);
  }

  void breadCrumbScrollToEnd() {
    Future.delayed(Duration(milliseconds: 200), () {
      if (_breadCrumbScroller.hasClients) {
        _breadCrumbScroller.animateTo(
            _breadCrumbScroller.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.fastLinearToSlowEaseIn);
      }
    });
  }

  Widget headTools() {
    final theme = Theme.of(context);
    return Obx(() => Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: WorkspaceStyle.elevatedSurface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: BreadCrumb(
              items: getPathBreadCrumbItems(
                  controller.shortPath,
                  controller.options.value.isWindows,
                  controller.goToHomeDirectory, (list) {
                final home = controller.homePath;
                var path = home.startsWith(list.first) ? '' : home;
                for (final item in list) {
                  path = PathUtil.join(
                      path, item, controller.options.value.isWindows);
                }
                controller.openDirectory(path);
              }),
              divider: Icon(Icons.chevron_right_rounded,
                  size: 14, color: theme.hintColor),
              overflow: ScrollableOverflow(controller: _breadCrumbScroller),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(translate('Home')),
                  onPressed: controller.goToHomeDirectory,
                ),
                for (final entry in controller.directory.value.entries
                    .where((entry) => entry.isDirectory)
                    .take(3))
                  Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(entry.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () => controller.openDirectory(entry.path),
                      )),
                if (!(isIOS && isLocal) && !(isAndroid && isLocal))
                  Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('/'),
                        onPressed: () => controller.openDirectory(
                            controller.options.value.isWindows
                                ? PathUtil.windowsContext
                                    .rootPrefix(controller.directory.value.path)
                                : '/'),
                      )),
                IconButton(
                    tooltip: translate('Back'),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.goBack),
                IconButton(
                    tooltip: translate('Parent directory'),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.goToParentDirectory),
              ]),
            ),
          ),
        ]));
  }

  Widget listTail() => Obx(() => MobileFileLocationFooter(
        path: AndroidDocuments.displayPath(controller.directory.value.path),
        summary:
            '${translate("Total")}: ${controller.directory.value.entries.length} ${translate("items")}',
      ));

  List<BreadCrumbItem> getPathBreadCrumbItems(String shortPath, bool isWindows,
      void Function() onHome, void Function(List<String>) onPressed) {
    final list = PathUtil.split(shortPath, isWindows);
    final breadCrumbList = [
      BreadCrumbItem(
          content: IconButton(
        icon: const Icon(Icons.home_outlined, size: 16),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        onPressed: onHome,
      ))
    ];
    breadCrumbList.addAll(list.asMap().entries.map((e) => BreadCrumbItem(
        content: TextButton(
            child: Text(e.value),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              textStyle: const TextStyle(fontSize: 11),
              foregroundColor: Theme.of(context).hintColor,
            ),
            onPressed: () => onPressed(list.sublist(0, e.key + 1))))));
    return breadCrumbList;
  }
}

Widget fileManagerSortButton(FileController controller) =>
    PopupMenuButton<SortBy>(
      tooltip: translate('Sort by'),
      icon: const Icon(Icons.swap_vert_rounded, size: 18),
      itemBuilder: (context) => SortBy.values
          .map((sort) => PopupMenuItem(
              value: sort, child: Text(translate(sort.toString()))))
          .toList(),
      onSelected: (sort) => controller.changeSortStyle(sort,
          ascending: controller.sortBy.value == sort
              ? !controller.sortAscending
              : true),
    );

class BottomSheetBody extends StatelessWidget {
  BottomSheetBody(
      {required this.leading,
      required this.title,
      required this.text,
      this.onCanceled,
      this.actions});

  final Widget leading;
  final String title;
  final String text;
  final VoidCallback? onCanceled;
  final List<IconButton>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Material(
          color: theme.cardColor,
          elevation: 4,
          shadowColor: Colors.black.withOpacity(.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: WorkspaceStyle.strongBorder(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: LayoutBuilder(builder: (context, bounds) {
              final info = Row(children: [
                IconTheme.merge(
                    data: IconThemeData(color: theme.colorScheme.primary),
                    child: leading),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ])),
              ]);
              final controls = Wrap(alignment: WrapAlignment.end, children: [
                ...?actions,
                IconButton(
                    tooltip: translate('Cancel'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onCanceled),
              ]);
              if (bounds.maxWidth < 420 && (actions?.length ?? 0) > 1) {
                return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [info, controls]);
              }
              return Row(children: [
                Expanded(child: info),
                Flexible(fit: FlexFit.loose, child: controls)
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class FileManagerSideSwitcher extends StatelessWidget {
  const FileManagerSideSwitcher({
    this.remoteName = '',
    required this.showLocal,
    required this.onChanged,
  });

  final bool showLocal;
  final String remoteName;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    Widget item(bool local, String label, IconData icon) {
      final active = showLocal == local;
      return Expanded(
          child: Semantics(
              selected: active,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(local),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                          child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : theme.hintColor,
                        ),
                      )),
                    ],
                  ),
                ),
              )));
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(true, translate('Local'),
              isIOS ? Icons.phone_iphone_rounded : Icons.phone_android_rounded),
          const SizedBox(width: 2),
          item(
              false,
              '${translate('Remote')}${remoteName.isEmpty ? '' : ' · $remoteName'}',
              Icons.desktop_windows_rounded),
        ],
      ),
    );
  }
}
