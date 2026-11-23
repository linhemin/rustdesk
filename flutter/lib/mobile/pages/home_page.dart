import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../native/apple_workspace_navigation.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'ios_files_page.dart';
import 'connection_page.dart';
import '../android_sliding_navigation_bar.dart';
import 'scan_page.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  bool get isChatPageCurrentTab => isAndroid
      ? _selectedIndex == _chatPageTabIndex
      : false; // change this when ios have chat page

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
  }

  void initPages() {
    _pages.clear();
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
      if (isIOS) _pages.add(IOSFilesPage());
    }
    if (isAndroid && !bind.isOutgoingOnly()) {
      _chatPageTabIndex = _pages.length;
      _pages.addAll([ChatPage(type: ChatPageType.mobileMain), ServerPage()]);
    }
    _pages.add(SettingsPage());
    if (_selectedIndex >= _pages.length) _selectedIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          extendBody: isIOS && _pages.length > 1,
          // backgroundColor: MyTheme.grayBg,
          appBar: isIOS && _pages[_selectedIndex] is SettingsPage
              ? null
              : AppBar(
                  toolbarHeight:
                      isIOS && _pages[_selectedIndex] is ConnectionPage
                          ? 48
                          : null,
                  titleSpacing: isIOS ? 16 : null,
                  centerTitle: !isIOS,
                  title: isIOS
                      ? Row(children: [
                          if (_pages[_selectedIndex] is ConnectionPage &&
                              !bind.isCustomClient())
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Text('R',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            )
                          else
                            loadIcon(26),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(
                                  _pages[_selectedIndex] is SettingsPage
                                      ? _pages[_selectedIndex].title
                                      : bind.mainGetAppNameSync(),
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      _pages[_selectedIndex] is ConnectionPage
                                          ? const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.3)
                                          : null)),
                        ])
                      : appTitle(),
                  actions: [
                    ..._pages.elementAt(_selectedIndex).appBarActions,
                    if (isIOS && _pages[_selectedIndex] is ConnectionPage)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: IconButton(
                          tooltip: translate('Scan QR code'),
                          onPressed: () => ScanPage.openConnection(context),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            backgroundColor: Theme.of(context).cardColor,
                            side: BorderSide(
                                color: Theme.of(context).dividerColor),
                          ),
                          icon: const Icon(Icons.qr_code_scanner_rounded,
                              size: 15),
                        ),
                      ),
                  ],
                ),
          bottomNavigationBar: _pages.length < 2 ||
                  (isIOS && MediaQuery.viewInsetsOf(context).bottom > 0)
              ? null
              : isIOS
                  ? AppleWorkspaceNavigation(
                      labels: _pages
                          .map((page) => page.title)
                          .toList(growable: false),
                      symbols: [
                        for (final page in _pages)
                          page is SettingsPage
                              ? 'gearshape'
                              : page is ConnectionPage
                                  ? 'display.2'
                                  : 'folder'
                      ],
                      selected: _selectedIndex,
                      compact: MediaQuery.sizeOf(context).shortestSide < 600,
                      onSelect: (index) =>
                          setState(() => _selectedIndex = index),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                      ),
                      child: AndroidSlidingNavigationBar(
                          child: BottomNavigationBar(
                        key: navigationBarKey,
                        backgroundColor: Theme.of(context).cardColor,
                        elevation: 0,
                        items: _pages
                            .map((page) => BottomNavigationBarItem(
                                icon: page.icon, label: page.title))
                            .toList(),
                        currentIndex: _selectedIndex,
                        type: BottomNavigationBarType.fixed,
                        selectedItemColor:
                            Theme.of(context).colorScheme.primary,
                        unselectedItemColor: Theme.of(context).hintColor,
                        onTap: (index) => setState(() {
                          // close chat overlay when go chat page
                          if (_selectedIndex != index) {
                            _selectedIndex = index;
                            if (isChatPageCurrentTab) {
                              gFFI.chatModel.hideChatIconOverlay();
                              gFFI.chatModel.hideChatWindowOverlay();
                              gFFI.chatModel.mobileClearClientUnread(
                                  gFFI.chatModel.currentKey.connId);
                            }
                          }
                        }),
                      )),
                    ),
          body: isIOS
              ? IndexedStack(index: _selectedIndex, children: _pages)
              : _pages.elementAt(_selectedIndex),
        ));
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text(bind.mainGetAppNameSync());
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      // backgroundColor: MyTheme.grayBg,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    var loginMethod = '';
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        case '--request-approval':
          loginMethod = 'request-approval';
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          loginMethod: loginMethod,
          password: password);
    }
  }
}
