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
        // backgroundColor: MyTheme.grayBg,
        appBar: AppBar(
          leading: Row(children: [
            IconButton(
                icon: Icon(Icons.close),
                onPressed: () => clientClose(gFFI.sessionId, gFFI)),
          ]),
          centerTitle: true,
          title: _LocalRemoteSegment(
            showLocal: showLocal,
            onChanged: (local) {
              if (local != showLocal) setState(() => showLocal = local);
            },
          ),
          actions: [
            PopupMenuButton<String>(
                tooltip: "",
                icon: Icon(Icons.more_vert),
                itemBuilder: (context) {
                  return [
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
                  if (v == 'workspace' || v == 'choose_folder') {
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
                                  labelText:
                                      translate("Please enter the folder name"),
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
                                if (!PathUtil.validName(
                                    name.value.text,
                                    currentFileController
                                        .options.value.isWindows)) {
                                  setState(() {
                                    errorText =
                                        translate("Invalid folder name");
                                  });
                                  return;
                                }
                                currentFileController.createDir(PathUtil.join(
                                    currentDir.path,
                                    name.value.text,
                                    currentOptions.isWindows));
                                close();
                              }
                            })
                          ]);
                    });
                  } else if (v == "hidden") {
                    currentFileController.toggleShowHidden();
                  }
                }),
          ],
        ),
        body: showLocal
            ? FileManagerView(
                controller: model.localController,
                selectMode: selectMode,
              )
            : FileManagerView(
                controller: model.remoteController,
                selectMode: selectMode,
              ),
        bottomSheet: bottomSheet(),
      ));

  Widget? bottomSheet() {
    return Obx(() {
      final selectedItems = getActiveSelectedItems();
      final jobTable = model.jobController.jobTable;

      final localLabel = selectedItems?.isLocal == null
          ? ""
          : " [${selectedItems!.isLocal ? translate("Local") : translate("Remote")}]";
      if (!(selectMode.value == SelectMode.none)) {
        final selectedItemsLen =
            "${selectedItems?.items.length ?? 0} ${translate("items")}";
        if (selectedItems == null ||
            selectedItems.items.isEmpty ||
            selectMode.value.eq(showLocal)) {
          return BottomSheetBody(
              leading: Icon(Icons.check),
              title: translate("Selected"),
              text: selectedItemsLen + localLabel,
              onCanceled: () {
                selectedItems?.items.clear();
                selectMode.value = SelectMode.none;
                setState(() {});
              },
              actions: [
                if (isAndroid &&
                    !AndroidDocuments.isPath(currentDir.path) &&
                    selectedItems?.isLocal == true &&
                    selectedItems?.items.isNotEmpty == true) ...[
                  if (selectedItems!.items.length == 1 &&
                      selectedItems!.items.single.isFile)
                    IconButton(
                      tooltip: translate("Save as"),
                      icon: Icon(Icons.save_alt),
                      onPressed: () =>
                          _exportFile(selectedItems!.items.single),
                    )
                  else
                    IconButton(
                      tooltip: translate("Export"),
                      icon: Icon(Icons.drive_folder_upload),
                      onPressed: () => _exportItems(selectedItems!),
                    ),
                ],
                IconButton(
                  icon: Icon(Icons.compare_arrows),
                  onPressed: () => setState(() => showLocal = !showLocal),
                ),
                IconButton(
                  icon: Icon(Icons.delete_forever),
                  onPressed: selectedItems != null
                      ? () async {
                          if (selectedItems.items.isNotEmpty) {
                            await currentFileController
                                .removeAction(selectedItems);
                            selectedItems.items.clear();
                            selectMode.value = SelectMode.none;
                          }
                        }
                      : null,
                )
              ]);
        } else {
          return BottomSheetBody(
              leading: Icon(Icons.input),
              title: translate("Paste here?"),
              text: selectedItemsLen + localLabel,
              onCanceled: () {
                selectedItems.items.clear();
                selectMode.value = SelectMode.none;
                setState(() {});
              },
              actions: [
                IconButton(
                  icon: Icon(Icons.compare_arrows),
                  onPressed: () => setState(() => showLocal = !showLocal),
                ),
                IconButton(
                  icon: Icon(Icons.paste),
                  onPressed: () {
                    selectMode.value = SelectMode.none;
                    final otherSide = showLocal
                        ? model.remoteController
                        : model.localController;
                    final thisSideData =
                        DirectoryData(currentDir, currentOptions);
                    otherSide.sendFiles(selectedItems, thisSideData);
                    selectedItems.items.clear();
                    selectMode.value = SelectMode.none;
                  },
                )
              ]);
        }
      }

      if (jobTable.isEmpty) {
        return Offstage();
      }

      // Find the first job that is in progress (the one actually transferring data)
      // Rust backend processes jobs sequentially, so the first inProgress job is the active one
      final activeJob = jobTable
              .firstWhereOrNull((job) => job.state == JobState.inProgress) ??
          jobTable.last;

      switch (activeJob.state) {
        case JobState.inProgress:
          return BottomSheetBody(
            leading: CircularProgressIndicator(),
            title: translate("Waiting"),
            text: "${readableFileSize(activeJob.speed)}/s",
            onCanceled: () {
              model.jobController.cancelJob(activeJob.id);
              jobTable.clear();
            },
          );
        case JobState.done:
          return BottomSheetBody(
            leading: Icon(Icons.check),
            title: "${translate("Successful")}!",
            text: activeJob.display(),
            onCanceled: () => jobTable.clear(),
          );
        case JobState.error:
          return BottomSheetBody(
            leading: Icon(Icons.error),
            title: "${translate("Error")}!",
            text: "",
            onCanceled: () => jobTable.clear(),
          );
        case JobState.none:
          break;
        case JobState.paused:
          // TODO: Handle this case.
          break;
      }
      return Offstage();
    });
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

  FileManagerView({required this.controller, required this.selectMode});

  @override
  State<StatefulWidget> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  final _listScrollController = ScrollController();
  final _breadCrumbScroller = ScrollController();
  late final ascending = Rx<bool>(controller.sortAscending);

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
        return ListView.builder(
          controller: _listScrollController,
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index >= entries.length) {
              return listTail();
            }
            var selected = false;
            if (widget.selectMode.value != SelectMode.none) {
              selected = _selectedItems.items.contains(entries[index]);
            }

            final sizeStr = entries[index].isFile
                ? readableFileSize(entries[index].size.toDouble())
                : "";

            final showCheckBox = () {
              return widget.selectMode.value != SelectMode.none &&
                  widget.selectMode.value.eq(controller.selectedItems.isLocal);
            }();
            final theme = Theme.of(context);
            final primary = theme.colorScheme.primary;
            final entry = entries[index];
            final (badgeIcon, badgeColor) = _fileEntryVisual(entry);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: entry.isDrive
                      ? Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(Icons.storage_rounded,
                              size: 20, color: primary),
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(badgeIcon, size: 20, color: badgeColor),
                        ),
                  title: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  selected: selected,
                  subtitle: entry.isDrive
                      ? null
                      : Text(
                          "${entry.lastModified().toString().replaceAll(".000", "")}${sizeStr.isEmpty ? '' : '  ·  $sizeStr'}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.hintColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                  trailing: entry.isDrive
                      ? Icon(Icons.chevron_right_rounded,
                          size: 18, color: theme.hintColor)
                      : showCheckBox
                          ? Checkbox(
                              shape: const CircleBorder(),
                              value: selected,
                              onChanged: (v) {
                                if (v == null) return;
                                if (v && !selected) {
                                  _selectedItems.add(entry);
                                } else if (!v && selected) {
                                  _selectedItems.remove(entry);
                                }
                                setState(() {});
                              })
                          : PopupMenuButton<String>(
                              tooltip: "",
                              icon: Icon(Icons.more_horiz_rounded,
                                  color: theme.hintColor),
                              itemBuilder: (context) {
                                return [
                                  PopupMenuItem(
                                    child: Text(translate("Delete")),
                                    value: "delete",
                                  ),
                                  PopupMenuItem(
                                    child: Text(translate("Multi Select")),
                                    value: "multi_select",
                                  ),
                                  PopupMenuItem(
                                    child: Text(translate("Properties")),
                                    value: "properties",
                                    enabled: false,
                                  ),
                                  if (!entry.isDrive &&
                                      versionCmp(gFFI.ffiModel.pi.version,
                                              "1.3.0") >=
                                          0)
                                    PopupMenuItem(
                                      child: Text(translate("Rename")),
                                      value: "rename",
                                    )
                                ];
                              },
                              onSelected: (v) {
                                if (v == "delete") {
                                  final items = SelectedItems(isLocal: isLocal);
                                  items.add(entry);
                                  controller.removeAction(items);
                                } else if (v == "multi_select") {
                                  _selectedItems.clear();
                                  widget.selectMode.toggle(isLocal);
                                  setState(() {});
                                } else if (v == "rename") {
                                  controller.renameAction(entry, isLocal);
                                }
                              }),
                  onTap: () {
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
                    }
                  },
                  onLongPress: entry.isDrive
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

  (IconData, Color) _fileEntryVisual(Entry entry) {
    if (entry.isDirectory) return (Icons.folder_rounded, WorkspaceStyle.amber);
    final lower = entry.name.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi')) {
      return (Icons.movie_outlined, WorkspaceStyle.purple);
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.rar')) {
      return (Icons.inventory_2_outlined, WorkspaceStyle.green);
    }
    if (lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.rs') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.js') ||
        lower.endsWith('.py')) {
      return (Icons.code_rounded, WorkspaceStyle.blue);
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return (Icons.image_outlined, WorkspaceStyle.indigo);
    }
    if (lower.endsWith('.pdf')) {
      return (Icons.description_outlined, WorkspaceStyle.red);
    }
    return (Icons.insert_drive_file_outlined, WorkspaceStyle.neutralTile);
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: WorkspaceStyle.elevatedSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(child: Obx(() {
            final home = controller.options.value.home;
            final isWindows = controller.options.value.isWindows;
            return BreadCrumb(
              items: getPathBreadCrumbItems(controller.shortPath, isWindows,
                  () => controller.goToHomeDirectory(), (list) {
                var path = "";
                if (home.startsWith(list[0])) {
                  // absolute path
                  for (var item in list) {
                    path = PathUtil.join(path, item, isWindows);
                  }
                } else {
                  path += home;
                  for (var item in list) {
                    path = PathUtil.join(path, item, isWindows);
                  }
                }
                controller.openDirectory(path);
              }),
              divider: Icon(Icons.chevron_right_rounded,
                  size: 16, color: theme.hintColor),
              overflow: ScrollableOverflow(controller: _breadCrumbScroller),
            );
          })),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                onPressed: controller.goBack,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                onPressed: controller.goToParentDirectory,
              ),
              PopupMenuButton<SortBy>(
                  tooltip: "",
                  icon: const Icon(Icons.sort_rounded, size: 18),
                  itemBuilder: (context) {
                    return SortBy.values
                        .map((e) => PopupMenuItem(
                              child: Text(translate(e.toString())),
                              value: e,
                            ))
                        .toList();
                  },
                  onSelected: (sortBy) {
                    if (controller.sortBy.value == sortBy) {
                      ascending.value = !controller.sortAscending;
                    } else {
                      ascending.value = true;
                    }
                    controller.changeSortStyle(sortBy,
                        ascending: ascending.value);
                  }),
            ],
          )
        ],
      ),
    );
  }

  Widget listTail() => Obx(() => Container(
        height: 100,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(30, 5, 30, 0),
              child: Text(
                AndroidDocuments.displayPath(controller.directory.value.path),
                style: TextStyle(color: MyTheme.darkGray),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(2),
              child: Text(
                "${translate("Total")}: ${controller.directory.value.entries.length} ${translate("items")}",
                style: TextStyle(color: MyTheme.darkGray),
              ),
            )
          ],
        ),
      ));

  List<BreadCrumbItem> getPathBreadCrumbItems(String shortPath, bool isWindows,
      void Function() onHome, void Function(List<String>) onPressed) {
    final list = PathUtil.split(shortPath, isWindows);
    final breadCrumbList = [
      BreadCrumbItem(
          content: IconButton(
        icon: Icon(Icons.home_filled),
        onPressed: onHome,
      ))
    ];
    breadCrumbList.addAll(list.asMap().entries.map((e) => BreadCrumbItem(
        content: TextButton(
            child: Text(e.value),
            style:
                ButtonStyle(minimumSize: MaterialStateProperty.all(Size(0, 0))),
            onPressed: () => onPressed(list.sublist(0, e.key + 1))))));
    return breadCrumbList;
  }
}

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
  BottomSheet build(BuildContext context) {
    final theme = Theme.of(context);
    return BottomSheet(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: theme.dividerColor),
      ),
      builder: (context) => SafeArea(
          top: false,
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
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(text,
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
          )),
      onClosing: () {},
      enableDrag: false,
    );
  }
}

class _LocalRemoteSegment extends StatelessWidget {
  const _LocalRemoteSegment({
    required this.showLocal,
    required this.onChanged,
  });

  final bool showLocal;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    Widget item(bool local, String label, IconData icon) {
      final active = showLocal == local;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(local),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: active ? Colors.white : theme.hintColor),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : theme.hintColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WorkspaceStyle.elevatedSurface(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(true, translate('Local'),
              isIOS ? Icons.phone_iphone_rounded : Icons.phone_android_rounded),
          const SizedBox(width: 2),
          item(false, translate('Remote'), Icons.desktop_windows_rounded),
        ],
      ),
    );
  }
}
