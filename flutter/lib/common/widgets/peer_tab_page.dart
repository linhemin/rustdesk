import 'dart:async';
import 'dart:ui' as ui;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:rustdesk_ui/rustdesk_ui.dart';
import 'package:flutter_hbb/common/widgets/address_book.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/my_group.dart';
import 'package:flutter_hbb/common/widgets/owned_devices.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/common/widgets/workspace.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/desktop/widgets/material_mod_popup_menu.dart'
    as mod_menu;
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

class PeerTabPage extends StatefulWidget {
  const PeerTabPage({Key? key}) : super(key: key);
  @override
  State<PeerTabPage> createState() => _PeerTabPageState();
}

class _TabEntry {
  final Widget widget;
  final Function({dynamic hint})? load;
  _TabEntry(this.widget, [this.load]);
}

EdgeInsets? _menuPadding() {
  return (isDesktop || isWebDesktop) ? kDesktopMenuPadding : null;
}

bool _usesIPhoneToolbar(BuildContext context) =>
    !isWeb && Theme.of(context).platform == TargetPlatform.iOS;

class _PeerTabPageState extends State<PeerTabPage>
    with SingleTickerProviderStateMixin {
  final List<_TabEntry> entries = [
    _TabEntry(RecentPeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(FavoritePeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(DiscoveredPeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(
        AddressBook(
          menuPadding: _menuPadding(),
        ),
        ({dynamic hint}) => gFFI.abModel.pullAb(
            force: hint == null ? ForcePullAb.listAndCurrent : null,
            quiet: false)),
    _TabEntry(
      MyGroup(
        menuPadding: _menuPadding(),
      ),
      ({dynamic hint}) => gFFI.groupModel.pull(force: hint == null),
    ),
    _TabEntry(
      OwnedDevices(menuPadding: _menuPadding()),
      ({dynamic hint}) => gFFI.userModel.refreshOwnedDevices(force: hint == null),
    ),
  ];
  RelativeRect? mobileTabContextMenuPos;

  final isOptVisiableFixed = isOptionFixed(kOptionPeerTabVisible);

  _PeerTabPageState() {
    _loadLocalOptions();
  }

  void _loadLocalOptions() {
    final uiType = bind.getLocalFlutterOption(k: kOptionPeerCardUiType);
    if (uiType != '') {
      peerCardUiType.value = int.parse(uiType) == 0
          ? PeerUiType.grid
          : int.parse(uiType) == 1
              ? PeerUiType.tile
              : PeerUiType.list;
    }
    hideAbTagsPanel.value =
        bind.mainGetLocalOption(key: kOptionHideAbTagsPanel) == 'Y';
  }

  Future<void> handleTabSelection(int tabIndex) async {
    if (tabIndex < entries.length) {
      if (tabIndex != gFFI.peerTabModel.currentTab) {
        gFFI.peerTabModel.setCurrentTabCachedPeers([]);
      }
      gFFI.peerTabModel.setCurrentTab(tabIndex);
      entries[tabIndex].load?.call(hint: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    final iPhone = _usesIPhoneToolbar(context);
    Widget selectionWrap(Widget widget) {
      return model.multiSelectionMode ? createMultiSelectionBar(model) : widget;
    }

    return Column(
      textBaseline: TextBaseline.ideographic,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() => SizedBox(
              height: iPhone
                  ? 44
                  : usesWorkspaceStyle
                      ? 40
                      : 32,
              child: Container(
                padding: stateGlobal.isPortrait.isTrue
                    ? EdgeInsets.symmetric(horizontal: 2)
                    : null,
                child: selectionWrap(Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                        child: iPhone
                            ? _iPhoneCollection(context, model)
                            : visibleContextMenuListener(
                                _createSwitchBar(context))),
                    if (!iPhone && stateGlobal.isPortrait.isTrue)
                      ..._portraitRightActions(context)
                    else if (!iPhone)
                      ..._landscapeRightActions(context)
                  ],
                )),
              ),
            ).paddingOnly(right: stateGlobal.isPortrait.isTrue ? 0 : 12)),
        if (iPhone)
          Obx(() => peerSearchText.value.isEmpty
              ? const SizedBox.shrink()
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: InputChip(
                    label: Text('${translate('Search')}: ${peerSearchText.value}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    deleteButtonTooltipMessage: translate('Clear'),
                    onDeleted: () {
                      peerSearchTextController.clear();
                      peerSearchText.value = '';
                    },
                  ),
                )),
        _createPeersView(),
      ],
    );
  }

  Widget _createSwitchBar(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    final labeled = usesWorkspaceStyle && (isWindows || isMacOS || isLinux || isWebDesktop);
    final canScroll = labeled || model.isVisibleEnabled[PeerTabIndex.owned.index];
    var counter = -1;
    return ReorderableListView(
        buildDefaultDragHandles: false,
        onReorder: model.reorder,
        scrollDirection: Axis.horizontal,
        physics: canScroll ? null : const NeverScrollableScrollPhysics(),
        children: model.visibleEnabledOrderedIndexs.map((t) {
          final selected = model.currentTab == t;
          final color = selected
              ? MyTheme.tabbar(context).selectedTextColor
              : MyTheme.tabbar(context).unSelectedTextColor?.withOpacity(0.5);
          final decoBorder = BoxDecoration(
            color: usesWorkspaceStyle
                ? Theme.of(context).cardColor
                : Theme.of(context).colorScheme.primary.withOpacity(.12),
            border: usesWorkspaceStyle
                ? Border.all(color: WorkspaceStyle.strongBorder(context))
                : null,
            borderRadius: BorderRadius.circular(8),
          );
          counter += 1;
          return ReorderableDragStartListener(
              key: ValueKey(t),
              index: counter,
              child: Tooltip(
                    preferBelow: false,
                    message: model.tabTooltip(t),
                    onTriggered: isMobile ? mobileShowTabVisibilityMenu : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: selected
                          ? Colors.transparent
                          : Theme.of(context).hoverColor,
                      child: Container(
                        decoration: selected ? decoBorder : null,
                        child: labeled
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(model.tabTooltip(t),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                            color: selected
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                : Theme.of(context).hintColor)),
                              ]).paddingSymmetric(horizontal: 8)
                            : Icon(model.tabIcon(t), color: color)
                                .paddingSymmetric(horizontal: 4),
                      ).paddingSymmetric(horizontal: 4),
                      onTap: isOptionFixed(kOptionPeerTabIndex)
                          ? null
                          : () async {
                              await handleTabSelection(t);
                              await bind.setLocalFlutterOption(
                                  k: kOptionPeerTabIndex, v: t.toString());
                            },
                    ),
                  ));
        }).toList());
  }

  Widget _iPhoneCollection(BuildContext context, PeerTabModel model) {
    final theme = Theme.of(context);
    String label(int tab) => switch (PeerTabIndex.values[tab]) {
          PeerTabIndex.recent => translate('Recent'),
          PeerTabIndex.lan => translate('LAN'),
          _ => model.tabTooltip(tab),
        };
    return Row(children: [
      Expanded(
          child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final tab in model.visibleEnabledOrderedIndexs)
            if (tab != PeerTabIndex.group.index ||
                tab == model.currentTab ||
                model.visibleEnabledOrderedIndexs.length == 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Semantics(
                  selected: tab == model.currentTab,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: tab == model.currentTab
                          ? theme.colorScheme.onSurface
                          : theme.cardColor,
                      foregroundColor: tab == model.currentTab
                          ? theme.scaffoldBackgroundColor
                          : theme.hintColor,
                      side: BorderSide(color: theme.dividerColor),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    onPressed: isOptionFixed(kOptionPeerTabIndex)
                        ? null
                        : () async {
                            await handleTabSelection(tab);
                            await bind.setLocalFlutterOption(
                                k: kOptionPeerTabIndex, v: tab.toString());
                          },
                    child: Text(label(tab)),
                  ),
                ),
              ),
        ]),
      )),
      IconButton(
        tooltip: translate('More'),
        onPressed: () => _showIPhoneCollectionMenu(context, model),
        icon: const Icon(Icons.more_horiz_rounded, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
      ),
    ]);
  }

  Future<void> _showIPhoneCollectionMenu(
      BuildContext context, PeerTabModel model) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: ListenableBuilder(
          listenable: model,
          builder: (context, _) {
            final tabs = model.visibleEnabledOrderedIndexs;
            return ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorder: model.reorder,
              header: Column(children: [
                ListTile(
                  title: Text(translate('More'),
                      style: Theme.of(context).textTheme.titleLarge),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: translate('Close'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                    PopupMenuButton<int>(
                      enabled: !isOptVisiableFixed,
                      tooltip: translate('Change view'),
                      icon: const Icon(Icons.tune_rounded),
                      onSelected: (tab) => model.setTabVisible(
                          tab, !model.isVisibleEnabled[tab]),
                      itemBuilder: (_) => [
                        for (final tab in model.orders)
                          if (model.isEnabled[tab])
                            CheckedPopupMenuItem(
                                value: tab,
                                checked: model.isVisibleEnabled[tab],
                                child: Text(model.tabTooltip(tab))),
                      ],
                    ),
                  ]),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(children: [
                    TextField(
                      controller: peerSearchTextController,
                      onChanged: (value) => peerSearchText.value = value,
                      decoration: InputDecoration(
                        hintText: translate('Search'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: translate('Clear'),
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            peerSearchTextController.clear();
                            peerSearchText.value = '';
                          },
                        ),
                      ),
                    ),
                    Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (model.currentTab != PeerTabIndex.recent.index)
                            PeerSortDropdown(),
                          if (model.currentTab == PeerTabIndex.ab.index ||
                              model.currentTab == PeerTabIndex.group.index)
                            TextButton.icon(
                              label: Text(translate('Refresh')),
                              icon: const Icon(Icons.refresh, size: 18),
                              onPressed: () =>
                                  entries[model.currentTab].load?.call(),
                            ),
                          if (_showWebConsole(model)) _openWebConsole(),
                          if (model.currentTab == PeerTabIndex.ab.index)
                            _toggleTags(),
                          if (model.currentTabCachedPeers.isNotEmpty)
                            TextButton.icon(
                              label: Text(translate('Select')),
                              icon: const Icon(Icons.check_box_outlined),
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                model.setMultiSelectionMode(true);
                              },
                            ),
                        ]),
                  ]),
                ),
              ]),
              children: [
                for (var i = 0; i < tabs.length; i++)
                  ListTile(
                    key: ValueKey(tabs[i]),
                    leading: Icon(model.tabIcon(tabs[i])),
                    title: Text(model.tabTooltip(tabs[i])),
                    selected: tabs[i] == model.currentTab,
                    enabled: !isOptionFixed(kOptionPeerTabIndex),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle_rounded),
                      ),
                    ),
                    onTap: () => Navigator.pop(sheetContext, tabs[i]),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await handleTabSelection(selected);
    await bind.setLocalFlutterOption(
        k: kOptionPeerTabIndex, v: selected.toString());
  }

  Widget _createPeersView() {
    final model = Provider.of<PeerTabModel>(context);
    Widget child;
    if (model.visibleEnabledOrderedIndexs.isEmpty) {
      child = visibleContextMenuListener(Row(
        children: [Expanded(child: InkWell())],
      ));
    } else {
      if (model.visibleEnabledOrderedIndexs.contains(model.currentTab)) {
        child = entries[model.currentTab].widget;
      } else {
        debugPrint("should not happen! currentTab not in visibleIndexs");
        Future.delayed(Duration.zero, () {
          model.setCurrentTab(model.visibleEnabledOrderedIndexs[0]);
        });
        child = entries[0].widget;
      }
    }
    return Expanded(
        child: child.marginSymmetric(
            vertical: (isDesktop || isWebDesktop) ? 12.0 : 6.0));
  }

  Widget _createRefresh(
      {required PeerTabIndex index, required RxBool loading}) {
    final model = Provider.of<PeerTabModel>(context);
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Offstage(
      offstage: model.currentTab != index.index,
      child: Tooltip(
        message: translate('Refresh'),
        child: RefreshWidget(
            onPressed: () {
              if (gFFI.peerTabModel.currentTab < entries.length) {
                entries[gFFI.peerTabModel.currentTab].load?.call();
              }
            },
            spinning: loading,
            child: RotatedBox(
                quarterTurns: 2,
                child: Icon(
                  Icons.refresh,
                  size: 18,
                  color: textColor,
                ))),
      ),
    );
  }

  Widget _createPeerViewTypeSwitch(BuildContext context) {
    return PeerViewDropdown();
  }

  Widget _createMultiSelection() {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
      toolTip: translate('Select'),
      context: context,
      touchTarget: _usesIPhoneToolbar(context),
      onTap: () {
        model.setMultiSelectionMode(true);
        if (isMobile && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: SvgPicture.asset(
        "assets/checkbox-outline.svg",
        width: 18,
        height: 18,
        colorFilter: svgColor(textColor),
      ),
    );
  }

  void mobileShowTabVisibilityMenu() {
    final model = gFFI.peerTabModel;
    final items = List<PopupMenuItem>.empty(growable: true);
    for (int i = 0; i < PeerTabModel.maxTabCount; i++) {
      if (!model.isEnabled[i]) continue;
      items.add(PopupMenuItem(
        height: kMinInteractiveDimension * 0.8,
        onTap: isOptVisiableFixed
            ? null
            : () => model.setTabVisible(i, !model.isVisibleEnabled[i]),
        enabled: !isOptVisiableFixed,
        child: Row(
          children: [
            Checkbox(
                value: model.isVisibleEnabled[i],
                onChanged: isOptVisiableFixed
                    ? null
                    : (_) {
                        model.setTabVisible(i, !model.isVisibleEnabled[i]);
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      }),
            Expanded(child: Text(model.tabTooltip(i))),
          ],
        ),
      ));
    }
    if (mobileTabContextMenuPos != null) {
      showMenu(
          context: context, position: mobileTabContextMenuPos!, items: items);
    }
  }

  Widget visibleContextMenuListener(Widget child) {
    if (!(isDesktop || isWebDesktop)) {
      return GestureDetector(
        onLongPressDown: (e) {
          final x = e.globalPosition.dx;
          final y = e.globalPosition.dy;
          mobileTabContextMenuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onLongPressUp: () {
          mobileShowTabVisibilityMenu();
        },
        child: child,
      );
    } else {
      return Listener(
          onPointerDown: (e) {
            if (e.kind != ui.PointerDeviceKind.mouse) {
              return;
            }
            if (e.buttons == 2) {
              showRightMenu(
                (CancelFunc cancelFunc) {
                  return visibleContextMenu(cancelFunc);
                },
                target: e.position,
              );
            }
          },
          child: child);
    }
  }

  Widget visibleContextMenu(CancelFunc cancelFunc) {
    final model = Provider.of<PeerTabModel>(context);
    final menu = List<MenuEntrySwitchSync>.empty(growable: true);
    for (int i = 0; i < model.orders.length; i++) {
      int tabIndex = model.orders[i];
      if (tabIndex < 0 || tabIndex >= PeerTabModel.maxTabCount) continue;
      if (!model.isEnabled[tabIndex]) continue;
      menu.add(MenuEntrySwitchSync(
          switchType: SwitchType.scheckbox,
          text: model.tabTooltip(tabIndex),
          currentValue: model.isVisibleEnabled[tabIndex],
          setter: (show) async {
            model.setTabVisible(tabIndex, show);
            // Do not hide the current menu (checkbox)
            // cancelFunc();
          },
          enabled: (!isOptVisiableFixed).obs));
    }
    return mod_menu.PopupMenu(
        items: menu
            .map((entry) => entry.build(
                context,
                const MenuConfig(
                  commonColor: MyTheme.accent,
                  height: 20.0,
                  dividerHeight: 12.0,
                )))
            .expand((i) => i)
            .toList());
  }

  Widget createMultiSelectionBar(PeerTabModel model) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Offstage(
          offstage: model.selectedPeers.isEmpty,
          child: Row(
            children: [
              deleteSelection(),
              addSelectionToFav(),
              addSelectionToAb(),
              editSelectionTags(),
            ],
          ),
        ),
        Row(
          children: [
            selectionCount(model.selectedPeers.length),
            selectAll(model),
            closeSelection(),
          ],
        )
      ],
    );
  }

  Widget deleteSelection() {
    final model = Provider.of<PeerTabModel>(context);
    if (model.currentTab == PeerTabIndex.group.index ||
        model.currentTab == PeerTabIndex.owned.index) {
      return Offstage();
    }
    return _hoverAction(
        context: context,
        toolTip: translate('Delete'),
        onTap: () {
          onSubmit() async {
            final peers = model.selectedPeers;
            switch (model.currentTab) {
              case 0:
                for (var p in peers) {
                  await bind.mainRemovePeer(id: p.id);
                }
                bind.mainLoadRecentPeers();
                break;
              case 1:
                final favs = (await bind.mainGetFav()).toList();
                peers.map((p) {
                  favs.remove(p.id);
                }).toList();
                await bind.mainStoreFav(favs: favs);
                bind.mainLoadFavPeers();
                break;
              case 2:
                for (var p in peers) {
                  await bind.mainRemoveDiscovered(id: p.id);
                }
                bind.mainLoadLanPeers();
                break;
              case 3:
                await gFFI.abModel.deletePeers(peers.map((p) => p.id).toList());
                break;
              default:
                break;
            }
            gFFI.peerTabModel.setMultiSelectionMode(false);
            if (model.currentTab != 3) showToast(translate('Successful'));
          }

          deleteConfirmDialog(onSubmit, translate('Delete'));
        },
        child: Icon(Icons.delete, color: Colors.red));
  }

  Widget addSelectionToFav() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage:
          model.currentTab != PeerTabIndex.recent.index, // show based on recent
      child: _hoverAction(
        context: context,
        toolTip: translate('Add to Favorites'),
        onTap: () async {
          final peers = model.selectedPeers;
          final favs = (await bind.mainGetFav()).toList();
          for (var p in peers) {
            if (!favs.contains(p.id)) {
              favs.add(p.id);
            }
          }
          await bind.mainStoreFav(favs: favs);
          model.setMultiSelectionMode(false);
          showToast(translate('Successful'));
        },
        child: Icon(PeerTabModel.icons[PeerTabIndex.fav.index]),
      ).marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget addSelectionToAb() {
    final model = Provider.of<PeerTabModel>(context);
    final addressbooks = gFFI.abModel.addressBooksCanWrite();
    if (model.currentTab == PeerTabIndex.ab.index) {
      addressbooks.remove(gFFI.abModel.currentName.value);
    }
    return Offstage(
      offstage: !gFFI.userModel.isLogin || addressbooks.isEmpty,
      child: _hoverAction(
        context: context,
        toolTip: translate('Add to address book'),
        onTap: () {
          final peers = model.selectedPeers.map((e) => Peer.copy(e)).toList();
          addPeersToAbDialog(peers);
          model.setMultiSelectionMode(false);
        },
        child: Icon(PeerTabModel.icons[PeerTabIndex.ab.index]),
      ).marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget editSelectionTags() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage: !gFFI.userModel.isLogin ||
          model.currentTab != PeerTabIndex.ab.index ||
          gFFI.abModel.currentAbTags.isEmpty,
      child: _hoverAction(
              context: context,
              toolTip: translate('Edit Tag'),
              onTap: () {
                editAbTagDialog(List.empty(), (selectedTags) async {
                  final peers = model.selectedPeers;
                  await gFFI.abModel.changeTagForPeers(
                      peers.map((p) => p.id).toList(), selectedTags);
                  model.setMultiSelectionMode(false);
                  showToast(translate('Successful'));
                });
              },
              child: Icon(Icons.tag))
          .marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget selectionCount(int count) {
    return Align(
      alignment: Alignment.center,
      child: Text('$count ${translate('Selected')}'),
    );
  }

  Widget selectAll(PeerTabModel model) {
    return Offstage(
      offstage:
          model.selectedPeers.length >= model.currentTabCachedPeers.length,
      child: _hoverAction(
        context: context,
        toolTip: translate('Select All'),
        onTap: () {
          model.selectAll();
        },
        child: Icon(Icons.select_all),
      ).marginOnly(left: 6),
    );
  }

  Widget closeSelection() {
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
            context: context,
            toolTip: translate('Close'),
            onTap: () {
              model.setMultiSelectionMode(false);
            },
            child: Icon(Icons.clear))
        .marginOnly(left: 6);
  }

  Widget _toggleTags() {
    return _hoverAction(
        context: context,
        toolTip: translate('Toggle Tags'),
        hoverableWhenfalse: hideAbTagsPanel,
        child: Icon(
          Icons.tag_rounded,
          size: 18,
        ),
        onTap: () async {
          await bind.mainSetLocalOption(
              key: kOptionHideAbTagsPanel,
              value: hideAbTagsPanel.value ? defaultOptionNo : "Y");
          hideAbTagsPanel.value = !hideAbTagsPanel.value;
        });
  }

  Widget _openWebConsole() {
    return _hoverAction(
        context: context,
        toolTip: translate('ab_web_console_tip'),
        child: Icon(
          Icons.open_in_new,
          size: 18,
        ),
        onTap: () async {
          final url = await bind.mainGetApiServer();
          if (await canLaunchUrlString(url)) {
            launchUrlString(url);
          }
        });
  }

  bool _showWebConsole(PeerTabModel model) =>
      model.currentTab == PeerTabIndex.ab.index &&
      gFFI.userModel.isLogin &&
      !gFFI.abModel.legacyMode.value &&
      gFFI.abModel.current.canWrite();

  List<Widget> _landscapeRightActions(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    return [
      const PeerSearchBar().marginOnly(right: 13),
      _createRefresh(
          index: PeerTabIndex.ab, loading: gFFI.abModel.currentAbLoading),
      _createRefresh(
          index: PeerTabIndex.group, loading: gFFI.groupModel.groupLoading),
      _createRefresh(
          index: PeerTabIndex.owned, loading: gFFI.userModel.ownedDevices.loading),
      Offstage(
        offstage: model.currentTabCachedPeers.isEmpty,
        child: _createMultiSelection(),
      ),
      if ((usesWorkspaceStyle &&
              const {TargetPlatform.macOS, TargetPlatform.windows}
                  .contains(Theme.of(context).platform)) ||
          ConnectionPeerList.of(context)?.onConnect == null)
        _createPeerViewTypeSwitch(context),
      Offstage(
        offstage: model.currentTab == PeerTabIndex.recent.index,
        child: PeerSortDropdown(),
      ),
      Offstage(
        offstage: !_showWebConsole(model),
        child: _openWebConsole(),
      ),
      Offstage(
        offstage: model.currentTab != PeerTabIndex.ab.index,
        child: _toggleTags(),
      ),
    ];
  }

  List<Widget> _portraitRightActions(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final leftIconSize = Theme.of(context).iconTheme.size ?? 24;
    final iPhone = _usesIPhoneToolbar(context);
    final leftActionsSize = iPhone
        ? 100.0
        : (leftIconSize + (4 + 4) * 2) * model.visibleEnabledOrderedIndexs.length;
    final availableWidth = screenWidth - 10 * 2 - leftActionsSize - 2 * 2;
    final searchWidth = 120;
    final otherActionWidth = iPhone ? 44 + 2 : 18 + 10;

    dropDown(List<Widget> menus) {
      final padding = 6.0;
      final textColor = Theme.of(context).textTheme.titleLarge?.color;
      return PullDownButton(
        buttonBuilder:
            (BuildContext context, Future<void> Function() showMenu) {
          return _hoverAction(
            context: context,
            toolTip: translate('More'),
            child: SvgPicture.asset(
              "assets/chevron_up_chevron_down.svg",
              width: 18,
              height: 18,
              colorFilter: svgColor(textColor),
            ),
            onTap: showMenu,
          );
        },
        routeTheme: PullDownMenuRouteTheme(
            width: menus.length * (otherActionWidth + padding * 2) * 1.0),
        itemBuilder: (context) => [
          PullDownMenuEntryImpl(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: menus
                  .map((e) =>
                      Material(child: e.paddingSymmetric(horizontal: padding)))
                  .toList(),
            ),
          )
        ],
      );
    }

    // Always show search, refresh
    List<Widget> actions = [
      const PeerSearchBar(),
      if (model.currentTab == PeerTabIndex.ab.index)
        _createRefresh(
            index: PeerTabIndex.ab, loading: gFFI.abModel.currentAbLoading),
      if (model.currentTab == PeerTabIndex.group.index)
        _createRefresh(
            index: PeerTabIndex.group, loading: gFFI.groupModel.groupLoading),
      if (model.currentTab == PeerTabIndex.owned.index)
        _createRefresh(
            index: PeerTabIndex.owned, loading: gFFI.userModel.ownedDevices.loading),
    ];
    final List<Widget> dynamicActions = [
      if (model.currentTabCachedPeers.isNotEmpty) _createMultiSelection(),
      if (model.currentTab != PeerTabIndex.recent.index) PeerSortDropdown(),
      if (_showWebConsole(model)) _openWebConsole(),
      if (model.currentTab == PeerTabIndex.ab.index) _toggleTags()
    ];
    final rightWidth = availableWidth -
        searchWidth -
        (actions.length == 2 ? otherActionWidth : 0);
    final availablePositions = (rightWidth ~/ otherActionWidth).clamp(0, dynamicActions.length);

    if (availablePositions < dynamicActions.length &&
        dynamicActions.length > 1) {
      if (availablePositions < 2) {
        actions.addAll([
          dropDown(dynamicActions),
        ]);
      } else {
        actions.addAll([
          ...dynamicActions.sublist(0, availablePositions - 1),
          dropDown(dynamicActions.sublist(availablePositions - 1)),
        ]);
      }
    } else {
      actions.addAll(dynamicActions);
    }
    return actions;
  }
}

class PeerSearchBar extends StatefulWidget {
  const PeerSearchBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PeerSearchBarState();
}

class _PeerSearchBarState extends State<PeerSearchBar> {
  var drawer = false;
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()
      ..addListener(() {
        if (!mounted) return;
        final hasFocus = _focusNode.hasFocus;
        setState(() => _focused = hasFocus);
        if (hasFocus) {
          peerSearchTextController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: peerSearchTextController.value.text.length);
        }
      });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return drawer
        ? _buildSearchBar()
        : _hoverAction(
            context: context,
            toolTip: translate('Search'),
            touchTarget: _usesIPhoneToolbar(context) || isMobile,
            padding: const EdgeInsets.only(right: 2),
            onTap: () {
              setState(() {
                drawer = true;
              });
            },
            child: Icon(
              Icons.search_rounded,
              color: Theme.of(context).hintColor,
            ));
  }

  Widget _buildSearchBar() {
    return Container(
          width: stateGlobal.isPortrait.isTrue ? 120 : 140,
          decoration: BoxDecoration(
            color: WorkspaceStyle.elevatedSurface(context),
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: Theme.of(context).hintColor,
                    ).marginSymmetric(horizontal: 4),
                    Expanded(
                      child: TextField(
                        autofocus: true,
                        controller: peerSearchTextController,
                        onChanged: (searchText) {
                          peerSearchText.value = searchText;
                        },
                        focusNode: _focusNode,
                        textAlign: TextAlign.start,
                        maxLines: 1,
                        cursorColor: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.5),
                        cursorHeight: 18,
                        cursorWidth: 1,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          filled: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 6),
                          hintText:
                              _focused ? null : translate("Search ID"),
                          hintStyle: TextStyle(
                              fontSize: 14, color: Theme.of(context).hintColor),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                    // Icon(Icons.close),
                    IconButton(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 2),
                      tooltip: translate('Close'),
                      onPressed: () {
                        setState(() {
                          peerSearchTextController.clear();
                          peerSearchText.value = "";
                          drawer = false;
                        });
                      },
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
  }
}

class PeerViewDropdown extends StatefulWidget {
  const PeerViewDropdown({super.key});

  @override
  State<PeerViewDropdown> createState() => _PeerViewDropdownState();
}

class _PeerViewDropdownState extends State<PeerViewDropdown> {
  @override
  Widget build(BuildContext context) {
    final List<PeerUiType> types = [
      PeerUiType.grid,
      PeerUiType.tile,
      PeerUiType.list
    ];
    final style = TextStyle(
        color: Theme.of(context).textTheme.titleLarge?.color,
        fontSize: MenuConfig.fontSize,
        fontWeight: FontWeight.normal);
    List<PopupMenuEntry> items = List.empty(growable: true);
    items.add(PopupMenuItem(
        height: 36,
        enabled: false,
        child: Text(translate("Change view"), style: style)));
    for (var e in PeerUiType.values) {
      items.add(PopupMenuItem(
          height: 36,
          child: Obx(() => Center(
                child: SizedBox(
                  height: 36,
                  child: getRadio<PeerUiType>(
                      Tooltip(
                          message: translate(types.indexOf(e) == 0
                              ? 'Big tiles'
                              : types.indexOf(e) == 1
                                  ? 'Small tiles'
                                  : 'List'),
                          child: Icon(
                            e == PeerUiType.grid
                                ? Icons.grid_view_rounded
                                : e == PeerUiType.list
                                    ? Icons.view_list_rounded
                                    : Icons.view_agenda_rounded,
                            size: 18,
                          )),
                      e,
                      peerCardUiType.value,
                      dense: true,
                      isOptionFixed(kOptionPeerCardUiType)
                          ? null
                          : (PeerUiType? v) async {
                              if (v != null) {
                                peerCardUiType.value = v;
                                setState(() {});
                                await bind.setLocalFlutterOption(
                                  k: kOptionPeerCardUiType,
                                  v: peerCardUiType.value.index.toString(),
                                );
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                }
                              }
                            }),
                ),
              ))));
    }

    var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
    return _hoverAction(
        context: context,
        toolTip: translate('Change view'),
        child: Obx(() => Icon(
              peerCardUiType.value == PeerUiType.grid
                  ? Icons.grid_view_rounded
                  : peerCardUiType.value == PeerUiType.list
                      ? Icons.view_list_rounded
                      : Icons.view_agenda_rounded,
              size: 18,
            )),
        onTapDown: (details) {
          final x = details.globalPosition.dx;
          final y = details.globalPosition.dy;
          menuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onTap: () => showMenu(
              context: context,
              position: menuPos,
              items: items,
              elevation: 8,
            ));
  }
}

class PeerSortDropdown extends StatefulWidget {
  const PeerSortDropdown({super.key});

  @override
  State<PeerSortDropdown> createState() => _PeerSortDropdownState();
}

class _PeerSortDropdownState extends State<PeerSortDropdown> {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: Theme.of(context).textTheme.titleLarge?.color,
        fontSize: MenuConfig.fontSize,
        fontWeight: FontWeight.normal);
    final items = <PopupMenuEntry<String>>[];
    items.add(PopupMenuItem<String>(
        height: 36,
        enabled: false,
        child: Text(translate("Sort by"), style: style)));
    for (var e in PeerSortType.values) {
      items.add(PopupMenuItem<String>(
          value: e,
          height: 36,
          child: Builder(builder: (menuContext) => Obx(() => Center(
                child: SizedBox(
                  height: 36,
                  child: getRadio(
                      Text(translate(e), style: style), e, peerSort.value,
                      dense: true, (String? v) {
                    if (v != null) Navigator.pop(menuContext, v);
                  }),
                ),
              )))));
    }

    var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
    return _hoverAction(
      context: context,
      toolTip: translate('Sort by'),
      child: Icon(
        Icons.sort_rounded,
        size: 18,
      ),
      onTapDown: (details) {
        final x = details.globalPosition.dx;
        final y = details.globalPosition.dy;
        menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      onTap: () async {
        final sort = await showMenu<String>(
          context: context,
          position: menuPos,
          items: items,
          elevation: 8,
        );
        if (sort == null || sort == peerSort.value) return;
        peerSort.value = sort;
        await bind.setLocalFlutterOption(k: kOptionPeerSorting, v: sort);
      },
    );
  }
}

class RefreshWidget extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final RxBool? spinning;
  const RefreshWidget(
      {super.key, required this.onPressed, required this.child, this.spinning});

  @override
  State<RefreshWidget> createState() => RefreshWidgetState();
}

class RefreshWidgetState extends State<RefreshWidget> {
  double turns = 0.0;
  bool hover = false;
  StreamSubscription<bool>? _spinSub;

  @override
  void initState() {
    super.initState();
    _subscribeSpinning();
  }

  @override
  void didUpdateWidget(covariant RefreshWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spinning != widget.spinning) {
      _spinSub?.cancel();
      _subscribeSpinning();
    }
  }

  void _subscribeSpinning() {
    _spinSub = widget.spinning?.listen((v) {
      if (v && mounted) {
        setState(() {
          turns += 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _spinSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(
      color: Theme.of(context).hoverColor,
      borderRadius: BorderRadius.circular(6),
    );
    return AnimatedRotation(
        turns: turns,
        duration: const Duration(milliseconds: 200),
        onEnd: () {
          if (widget.spinning?.value == true && mounted) {
            setState(() => turns += 1.0);
          }
        },
        child: Container(
          padding: EdgeInsets.all(4.0),
          margin: EdgeInsets.symmetric(horizontal: 1),
          decoration: hover ? deco : null,
          child: InkWell(
              onTap: () {
                if (mounted) setState(() => turns += 1.0);
                widget.onPressed();
              },
              onHover: (value) {
                if (mounted) {
                  setState(() {
                    hover = value;
                  });
                }
              },
              child: widget.child),
        ));
  }
}

Widget _hoverAction(
    {required BuildContext context,
    required Widget child,
    required Function() onTap,
    required String toolTip,
    GestureTapDownCallback? onTapDown,
    RxBool? hoverableWhenfalse,
    bool touchTarget = false,
    EdgeInsetsGeometry padding = const EdgeInsets.all(4.0)}) {
  final effectivePadding =
      isMobile ? const EdgeInsets.all(8.0) : padding;
  final deco = BoxDecoration(
    color: Theme.of(context).hoverColor,
    borderRadius: BorderRadius.circular(6),
  );
  return Tooltip(
    message: toolTip,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: Theme.of(context).hoverColor,
        onTap: onTap,
        onTapDown: onTapDown,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: (hoverableWhenfalse != null && !hoverableWhenfalse.value)
              ? deco
              : null,
          child: touchTarget
              ? SizedBox.square(dimension: 44, child: Center(child: child))
              : Container(padding: effectivePadding, child: child),
        ),
      ),
    ),
  );
}

class PullDownMenuEntryImpl extends StatelessWidget
    implements PullDownMenuEntry {
  final Widget child;
  const PullDownMenuEntryImpl({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
