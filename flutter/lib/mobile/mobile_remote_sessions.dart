import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
import '../consts.dart';
import '../models/model.dart';
import '../models/platform_model.dart';
import '../models/state_model.dart';
import 'pages/remote_page.dart';

class MobileRemoteSession {
  MobileRemoteSession(this.id);

  final String id;
  final openedAt = DateTime.now();
  final ffi = FFI(const Uuid().v4obj());
  bool started = false;
  bool suspended = false;
  bool presenting = false;

  Widget withModels(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ffi.ffiModel),
          ChangeNotifierProvider.value(value: ffi.imageModel),
          ChangeNotifierProvider.value(value: ffi.cursorModel),
          ChangeNotifierProvider.value(value: ffi.canvasModel),
        ],
        child: child,
      );

  Future<void> show(
    BuildContext context, {
    String loginMethod = '',
    String? password,
    bool? isSharedPassword,
    bool? forceRelay,
  }) async {
    final sessions = MobileRemoteSessions.sessions;
    if (ffi.closed || sessions.any((session) => session.presenting)) return;
    presenting = true;
    if (!sessions.contains(this)) sessions.add(this);
    stateGlobal.isInMainPage = false;
    ffi.onSessionClosed = () => unawaited(close());
    final route = MaterialPageRoute<void>(
      builder: (_) => withModels(RemotePage(
        id: id,
        loginMethod: loginMethod,
        password: password,
        isSharedPassword: isSharedPassword,
        forceRelay: forceRelay,
        workspaceSession: this,
      )),
    );
    try {
      await Navigator.of(context).push(route);
      await route.completed;
    } finally {
      presenting = false;
      if (!suspended || ffi.closed) await close();
      stateGlobal.isInMainPage = true;
    }
  }

  Future<void> setSuspended(bool value) async {
    await bind.sessionPeerOption(
      sessionId: ffi.sessionId,
      name: 'mobile-remote-suspended',
      value: value ? 'Y' : 'N',
    );
    suspended = value;
    ffi.mobileRemoteSuspended = value;
    final peer = ffi.ffiModel.pi;
    if (versionCmp(peer.version, '1.2.4') < 0) return;
    final displays = value
        ? <int>[]
        : peer.currentDisplay == kAllDisplayValue
            ? List.generate(peer.displays.length, (index) => index)
            : [peer.currentDisplay];
    await bind.sessionSwitchDisplay(
        isDesktop: false,
        sessionId: ffi.sessionId,
        value: Int32List.fromList(displays));
  }

  Future<void> close() async {
    MobileRemoteSessions.sessions.remove(this);
    ffi.dialogManager.dismissAll();
    if (started && !ffi.closed) await ffi.close();
  }
}

class MobileRemoteSessions {
  static final sessions = <MobileRemoteSession>[].obs;

  static Future<void> open(
    BuildContext context,
    String id, {
    String loginMethod = '',
    String? password,
    bool? isSharedPassword,
    bool? forceRelay,
  }) async {
    final index = sessions
        .indexWhere((session) => session.id == id && !session.ffi.closed);
    final session = index == -1 ? MobileRemoteSession(id) : sessions[index];
    await session.show(context,
        loginMethod: loginMethod,
        password: password,
        isSharedPassword: isSharedPassword,
        forceRelay: forceRelay);
  }
}
