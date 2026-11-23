import 'package:flutter_hbb/common/widgets/peer_udp_report.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse_widgets.dart';
import 'package:flutter_hbb/mobile/widgets/gesture_help.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/overlay.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/remote_input.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/shortcut_model.dart';
import '../../utils/image.dart';
import '../../utils/scale.dart';
import '../awesun/awesun_flutter_overlay.dart';
import '../awesun/awesun_native_bridge.dart';
import '../ios_p2p_diagnostics.dart';
import '../session_canvas_drag.dart';
import '../session_ime.dart';
import '../session_viewport.dart';
import '../widgets/dialog.dart';
import '../widgets/custom_scale_widget.dart';
import '../widgets/session_controls.dart';
import '../widgets/session_keyboard.dart';
import '../widgets/session_quality_monitor.dart';
import '../widgets/session_touchpad.dart';

final initText = '1' * 1024;

void updateIosSessionWakelock(UniqueKey key, AppLifecycleState? state) {
  if (state == AppLifecycleState.resumed) {
    WakelockManager.enable(key);
  } else if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached) {
    WakelockManager.disable(key);
  }
}

// Workaround for Android (default input method, Microsoft SwiftKey keyboard) when using physical keyboard.
// When connecting a physical keyboard, `KeyEvent.physicalKey.usbHidUsage` are wrong is using Microsoft SwiftKey keyboard.
// https://github.com/flutter/flutter/issues/159384
// https://github.com/flutter/flutter/issues/159383
void _disableAndroidSoftKeyboard({bool? isKeyboardVisible}) {
  if (isAndroid) {
    if (isKeyboardVisible != true) {
      // `enable_soft_keyboard` will be set to `true` when clicking the keyboard icon, in `openKeyboard()`.
      gFFI.invokeMethod("enable_soft_keyboard", false);
    }
  }
}

bool handleMobileLocalKeyEvent(KeyEvent event,
    {required bool remoteFocused, required InputModel inputModel}) {
  if (event is KeyUpEvent && inputModel.isViewOnly) {
    // View-only skips normal modifier cleanup; stale physical keys would
    // otherwise look like touch selections in the input helper.
    inputModel.handleKeyUpEventModifiers(event);
  }
  if (!remoteFocused &&
      event is KeyUpEvent &&
      const [
        PhysicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.controlRight,
        PhysicalKeyboardKey.altLeft,
        PhysicalKeyboardKey.altRight,
        PhysicalKeyboardKey.shiftLeft,
        PhysicalKeyboardKey.shiftRight,
        PhysicalKeyboardKey.metaLeft,
        PhysicalKeyboardKey.metaRight,
      ].contains(event.physicalKey)) {
    // Local UI may consume key-ups while the remote input path still owns
    // the modifiers pressed before focus moved.
    inputModel.handleKeyEvent(event);
  }
  return false;
}

class RemotePage extends StatefulWidget {
  RemotePage(
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
  State<RemotePage> createState() => _RemotePageState(id);
}

class _NativePointerBatch {
  _NativePointerBatch(this.target, this.pan);
  Offset target;
  Offset pan;
}

class _RemotePageState extends State<RemotePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _sessionOpened = DateTime.now();
  Timer? _timer;
  bool _showBar = !isWebDesktop;
  bool _showGestureHelp = false;
  String _value = '';
  Orientation? _currentOrientation;
  final _uniqueKey = UniqueKey();
  Timer? _iosKeyboardWorkaroundTimer;

  final _blockableOverlayState = BlockableOverlayState();

  final keyboardVisibilityController = KeyboardVisibilityController();
  late final StreamSubscription<bool> keyboardSubscription;
  late final FocusNode _mobileFocusNode =
      FocusNode(onKeyEvent: _handleSessionImeKey);
  final FocusNode _physicalFocusNode = FocusNode();
  var _showEdit = false; // use soft keyboard
  bool _showSessionKeyboard = false;
  Future<void> _virtualMouseInput = Future.value();
  bool _virtualMouseDown = false;
  final _sessionKeyboardKey = GlobalKey();
  final _sessionViewportKey = GlobalKey();
  bool _viewportUpdateScheduled = false;
  final _sessionIme = SessionIme();
  Future<void> _imeQueue = Future.value();

  Worker? _waylandKeyboardGateWorker;
  bool _waylandKeyboardGateInitialized = false;
  Worker? _nativeSessionReadiness;
  List<VoidCallback> _nativeActions = const [];
  List<Future<void> Function()> _nativeDisplayActions = const [];
  _NativePointerBatch? _nativePointerBatch;
  bool _savingNativeScreenshot = false;
  int? _nativeVideoTexture;
  bool _nativeFixedFps = false;
  bool _nativePerformanceBusy = false;
  int _nativePerformanceTarget = 60;
  Map<String, Object?> _lastNativePerformance = const {};
  ({bool obscured, double inset})? _nativePresentation;
  bool _nativeSessionRequested = false;
  bool _nativeSessionActive = false;
  late final _canvasDrag = SessionCanvasDrag(this, (delta) {
    final canvas = gFFI.canvasModel;
    if (!_usesAwesunOverlay ||
        !gFFI.ffiModel.touchMode ||
        gFFI.ffiModel.isPeerMobile ||
        canvas.locked) return false;
    return canvas.panDirectTouch(delta);
  });
  bool _nativePointerVisible = false;
  Rect? _nativeMouseViewport;
  bool _nativeMouseViewportScheduled = false;
  double _nativeKeyboardPanel = 0;
  double? _nativeSystemKeyboardTarget;
  ({Size full, double visible})? _nativeKeyboardViewport;
  late final AnimationController _nativeKeyboardShift =
      AnimationController.unbounded(vsync: this)
        ..addListener(() {
          gFFI.canvasModel.setNativeKeyboardOffset(_nativeKeyboardShift.value);
        });
  int _nativeSessionRevision = 0;
  late final _nativeSession = AwesunNativeBridge(
    inputModel: inputModel,
    cursorModel: gFFI.cursorModel,
    canvasPoint: (point) {
      final box = _sessionViewportKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return null;
      return box.globalToLocal(point);
    },
    canSendInput: () => mounted && _sessionReady && _canSendSessionInput,
    onClose: () {
      if (mounted) clientClose(sessionId, gFFI);
    },
    onCommand: _nativeCommand,
    onVirtualMove: _moveNativePointer,
    onVideoTexture: (id) {
      if (mounted && _nativeSessionActive && _nativeVideoTexture != id) {
        setState(() => _nativeVideoTexture = id);
        _syncNativePerformance();
      }
    },
    onPointerVisibility: (visible) {
      if (mounted && _nativePointerVisible != visible) {
        setState(() => _nativePointerVisible = visible);
      }
    },
    onVirtualClick: (button, point) {
      _nativePointerBatch = null;
      _queueVirtualMouse(() => _clickSessionMouse(button, nativePoint: point));
    },
    onVirtualDrag: (down, point) {
      _nativePointerBatch = null;
      down ? _holdVirtualMouse(nativePoint: point) : _releaseVirtualMouse();
    },
    onVirtualScroll: (steps, point) {
      _nativePointerBatch = null;
      _queueVirtualMouse(() async {
        if (await _moveToNativePointer(point) && mounted && _canSendSessionInput) {
          await inputModel.scroll(steps);
        }
      });
    },
  );

  InputModel get inputModel => gFFI.inputModel;
  SessionID get sessionId => gFFI.sessionId;

  final TextEditingController _textController =
      TextEditingController(text: initText);

  _RemotePageState(String id) {
    initSharedStates(id);
    gFFI.chatModel.voiceCallStatus.value = VoiceCallStatus.notStarted;
    gFFI.dialogManager.loadMobileActionsOverlayVisible();
  }

  @override
  void initState() {
    super.initState();
    if (isMobile) _textController.addListener(_sendSessionImeEdit);
    gFFI.ffiModel.updateEventListener(sessionId, widget.id);
    gFFI.start(
      widget.id,
      loginMethod: widget.loginMethod,
      password: widget.password,
      isSharedPassword: widget.isSharedPassword,
      forceRelay: widget.forceRelay,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    if (isIOS) {
      updateIosSessionWakelock(
          _uniqueKey, WidgetsBinding.instance.lifecycleState);
    } else {
      WakelockManager.enable(_uniqueKey);
    }
    _physicalFocusNode.requestFocus();
    HardwareKeyboard.instance.addHandler(_handleLocalKeyEvent);
    gFFI.inputModel.listenToMouse(true);
    gFFI.qualityMonitorModel.checkShowQualityMonitor(sessionId);
    keyboardSubscription =
        keyboardVisibilityController.onChange.listen(onSoftKeyboardChanged);
    gFFI.chatModel
        .changeCurrentKey(MessageKey(widget.id, ChatModel.clientModeID));
    _blockableOverlayState.applyFfi(gFFI);
    gFFI.imageModel.addCallbackOnFirstImage((String peerId) {
      gFFI.recordingModel
          .updateStatus(bind.sessionGetIsRecording(sessionId: gFFI.sessionId));
      if (gFFI.recordingModel.start) {
        showToast(translate('Automatically record outgoing sessions'));
      }
      _disableAndroidSoftKeyboard(
          isKeyboardVisible: keyboardVisibilityController.isVisible);
      // Seed shortcut action callbacks once the session is ready, so that
      // global keyboard shortcuts work even if the user never opens the
      // toolbar menu. The returned list is intentionally discarded — the
      // side effect of registering callbacks (inside toolbarControls) is
      // what we want here.
      if (mounted) {
        toolbarControls(context, widget.id, gFFI);
        // Mobile has no DesktopTabController, so tab-switch shortcuts will
        // log a no-handler debug line if a user binds one.
        registerSessionShortcutActions(gFFI);
        _registerMobileChatShortcut();
        registerToolbarShortcuts(context, widget.id, gFFI);
      }
    });
    WidgetsBinding.instance.addObserver(this);

    inputModel.keyboardInputAllowed = true;

    // Wayland sessions may use clipboard-based text input on the controlled side.
    // Require explicit user confirmation before allowing soft-keyboard and
    // clipboard-assisted text input. Physical keyboard events are not gated here.
    _waylandKeyboardGateWorker = ever(gFFI.ffiModel.pi.isSet, (bool isSet) {
      if (isSet) {
        _initWaylandKeyboardGateIfNeeded();
      }
    });
    if (gFFI.ffiModel.pi.isSet.value) {
      _initWaylandKeyboardGateIfNeeded();
    }
    if (isIOS) {
      final model = gFFI.ffiModel;
      _nativeSessionReadiness =
          everAll([model.pi.isSet, model.waitForFirstImage], (_) {
        unawaited(_syncNativeSession());
      });
      gFFI.qualityMonitorModel.addListener(_syncNativePerformance);
      gFFI.dialogManager.openDialog.addListener(_syncNativePresentation);
      gFFI.chatModel.chatWindowOpen.addListener(_syncNativePresentation);
      unawaited(_syncNativeSession());
    }
  }

  @override
  Future<void> dispose() async {
    if (isIOS) {
      WakelockManager.disable(_uniqueKey);
      _canvasDrag.detach();
    }
    _nativeSessionReadiness?.dispose();
    if (isIOS) {
      gFFI.qualityMonitorModel.removeListener(_syncNativePerformance);
      gFFI.dialogManager.openDialog.removeListener(_syncNativePresentation);
      gFFI.chatModel.chatWindowOpen.removeListener(_syncNativePresentation);
      if (_nativeSessionRevision != 0) _nativeSession.dispose();
    }
    if (isIOS) _nativeKeyboardShift.dispose();
    HardwareKeyboard.instance.removeHandler(_handleLocalKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _textController.removeListener(_sendSessionImeEdit);
    _releaseVirtualMouse();
    // Close the session up-front. `gFFI.close()` below only calls `sessionClose`
    // after several awaits (canvas save, image update, the `enable_soft_keyboard`
    // platform call), so if the app is backgrounded while this page is disposing,
    // dispose can be suspended before reaching it and the connection is never torn
    // down. The reconnect then re-attaches to the leaked session and is stuck on
    // "Connecting...". Dispatching it here makes teardown happen synchronously on
    // pop; the `sessionClose` in `gFFI.close()` becomes a no-op once removed.
    unawaited(bind.sessionClose(sessionId: sessionId));
    // https://github.com/flutter/flutter/issues/64935
    super.dispose();
    gFFI.dialogManager.hideMobileActionsOverlay(store: false);
    gFFI.inputModel.listenToMouse(false);
    gFFI.imageModel.disposeImage();
    gFFI.cursorModel.disposeImages();
    await gFFI.invokeMethod("enable_soft_keyboard", true);
    _mobileFocusNode.dispose();
    _physicalFocusNode.dispose();
    _textController.dispose();
    clearWaylandKeyboardPromptSuppressedForConnection(sessionId.toString());
    _waylandKeyboardGateWorker?.dispose();
    inputModel.keyboardInputAllowed = true;
    await gFFI.close();
    _timer?.cancel();
    _iosKeyboardWorkaroundTimer?.cancel();
    gFFI.dialogManager.dismissAll();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    if (!isIOS) WakelockManager.disable(_uniqueKey);
    await keyboardSubscription.cancel();
    removeSharedStates(widget.id);
    // `on_voice_call_closed` should be called when the connection is ended.
    // The inner logic of `on_voice_call_closed` will check if the voice call is active.
    // Only one client is considered here for now.
    gFFI.chatModel.onVoiceCallClosed("End connection");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isIOS) updateIosSessionWakelock(_uniqueKey, state);
    if (isIOS && state != AppLifecycleState.resumed) _canvasDrag.interrupt();
    if (state == AppLifecycleState.resumed) {
      trySyncClipboard();
    } else if (isMobile && _showSessionKeyboard) {
      _clearSessionModifiers();
    }
  }

  // For client side
  // When swithing from other app to this app, try to sync clipboard.
  void trySyncClipboard() {
    gFFI.invokeMethod("try_sync_clipboard");
  }

  bool _shouldGateKeyboardForWayland() {
    if (!(isAndroid || isIOS)) return false;
    final pi = gFFI.ffiModel.pi;
    return pi.platform == kPeerPlatformLinux && pi.isWayland;
  }

  void _initWaylandKeyboardGateIfNeeded() {
    if (!mounted) return;
    if (_waylandKeyboardGateInitialized) return;
    if (!_shouldGateKeyboardForWayland()) return;

    _waylandKeyboardGateInitialized = true;

    final allowWaylandKeyboard =
        mainGetPeerBoolOptionSync(widget.id, kPeerOptionAllowWaylandKeyboard);
    if (!shouldShowWaylandKeyboardPrompt(
      connectionId: sessionId.toString(),
      isWaylandPeer: _shouldGateKeyboardForWayland(),
      allowWaylandKeyboardRemembered: allowWaylandKeyboard,
    )) {
      inputModel.keyboardInputAllowed = true;
      return;
    }

    inputModel.keyboardInputAllowed = false;

    // Ensure soft keyboard is not active before user confirms.
    _showEdit = false;
    gFFI.invokeMethod("enable_soft_keyboard", false);
    _mobileFocusNode.unfocus();
    _physicalFocusNode.requestFocus();
    setState(() {});
  }

  // to-do: It should be better to use transparent color instead of the bgColor.
  // But for now, the transparent color will cause the canvas to be white.
  // I'm sure that the white color is caused by the Overlay widget in BlockableOverlay.
  // But I don't know why and how to fix it.
  Widget emptyOverlay(Color bgColor) => BlockableOverlay(
        /// the Overlay key will be set with _blockableOverlayState in BlockableOverlay
        /// see override build() in [BlockableOverlay]
        state: _blockableOverlayState,
        underlying: Container(
          color: bgColor,
        ),
      );

  void onSoftKeyboardChanged(bool visible) {
    if (!mounted) return;
    final chatHasFocus = gFFI.chatModel.inputNode.hasFocus;
    if (!visible) {
      if (isMobile && _showEdit && !chatHasFocus) {
        _showEdit = false;
        _mobileFocusNode.unfocus();
        _physicalFocusNode.requestFocus();
      }
      if (!_nativeSessionActive || chatHasFocus) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      }
      // [pi.version.isNotEmpty] -> check ready or not, avoid login without soft-keyboard
      if (gFFI.chatModel.chatWindowOverlayEntry == null &&
          gFFI.ffiModel.pi.version.isNotEmpty) {
        gFFI.invokeMethod("enable_soft_keyboard", false);
      }

      // Workaround for iOS: physical keyboard input fails after virtual keyboard is hidden
      // https://github.com/flutter/flutter/issues/39900
      // https://github.com/rustdesk/rustdesk/discussions/11843#discussioncomment-13499698 - Virtual keyboard issue
      if (isIOS && !chatHasFocus) {
        _iosKeyboardWorkaroundTimer?.cancel();
        _iosKeyboardWorkaroundTimer = Timer(Duration(milliseconds: 100), () {
          if (!mounted || _showEdit || gFFI.chatModel.inputNode.hasFocus) {
            return;
          }
          _physicalFocusNode.unfocus();
          _iosKeyboardWorkaroundTimer = Timer(Duration(milliseconds: 50), () {
            if (!mounted || _showEdit || gFFI.chatModel.inputNode.hasFocus) {
              return;
            }
            _physicalFocusNode.requestFocus();
          });
        });
      }
    } else {
      _iosKeyboardWorkaroundTimer?.cancel();
      _iosKeyboardWorkaroundTimer = null;
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        if (!mounted) return;
        if (!_nativeSessionActive || gFFI.chatModel.inputNode.hasFocus) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
              overlays: SystemUiOverlay.values);
        }
        if (_showEdit && !gFFI.chatModel.inputNode.hasFocus) {
          _mobileFocusNode.requestFocus();
        }
      });
    }
    // update for Scaffold
    setState(() {});
  }

  void _resetSessionIme() {
    _sessionIme.reset();
    _textController.value = SessionIme.initialValue;
  }

  bool get _canSendSessionIme =>
      _canSendSessionInput && inputModel.keyboardInputAllowed;

  void _sendSessionImeEdit() {
    if (!_showEdit || !_mobileFocusNode.hasFocus || !_canSendSessionIme) return;
    final value = _textController.value;
    final edit = _sessionIme.update(value);
    final restored = _sessionIme.restoreMarker(value);
    if (restored != null) _textController.value = restored;
    if (edit == null) return;
    final target = sessionId;
    final modifiers = _sessionModifiers;
    _imeQueue = _imeQueue
        .then((_) => _applySessionImeEdit(target, edit, modifiers))
        .catchError((Object error) {
      debugPrint('Remote IME input failed: ${error.runtimeType}');
    });
  }

  Future<void> _applySessionImeEdit(SessionID target, SessionImeEdit edit,
      Set<SessionModifier> modifiers) async {
    bool allowed() => mounted && sessionId == target && _canSendSessionIme;
    Future<void> press(String key, Set<SessionModifier> modifiers) =>
        bind.sessionInputKey(
          sessionId: target,
          name: key,
          down: false,
          press: true,
          alt: modifiers.contains(SessionModifier.alt),
          ctrl: modifiers.contains(SessionModifier.ctrl),
          shift: modifiers.contains(SessionModifier.shift),
          command: modifiers.contains(SessionModifier.meta),
        );

    for (var i = 0; i < edit.backspaces && allowed(); i++) {
      await press('VK_BACK', const {});
    }
    if (!allowed() || edit.text.isEmpty) return;
    if (edit.text.length == 1 && edit.text.codeUnitAt(0) < 128) {
      final key = switch (edit.text) {
        '\n' => 'VK_RETURN',
        ' ' => 'VK_SPACE',
        _ => edit.text,
      };
      await press(key, modifiers);
    } else {
      await bind.sessionInputString(sessionId: target, value: edit.text);
    }
  }

  KeyEventResult _handleSessionImeKey(FocusNode node, KeyEvent event) {
    if (!isMobile || !_showEdit || !_canSendSessionInput) {
      return KeyEventResult.ignored;
    }
    final composing = _textController.value.composing;
    final keyboard = HardwareKeyboard.instance;
    if (!useRemoteSessionKey(
      event.logicalKey,
      composing: composing.isValid && !composing.isCollapsed,
      shortcut: keyboard.isControlPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed,
    )) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && !isSessionImeModifier(event.logicalKey)) {
      _resetSessionIme();
    }
    return inputModel.handleKeyEvent(event);
  }

  void _handleIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    var i = newValue.length - 1;
    for (; i >= 0 && newValue[i] != '1'; --i) {}
    var j = oldValue.length - 1;
    for (; j >= 0 && oldValue[j] != '1'; --j) {}
    if (i < j) j = i;
    var subNewValue = newValue.substring(j + 1);
    var subOldValue = oldValue.substring(j + 1);

    // get common prefix of subNewValue and subOldValue
    var common = 0;
    for (;
        common < subOldValue.length &&
            common < subNewValue.length &&
            subNewValue[common] == subOldValue[common];
        ++common) {}

    // get newStr from subNewValue
    var newStr = "";
    if (subNewValue.length > common) {
      newStr = subNewValue.substring(common);
    }

    // Set the value to the old value and early return if is still composing. (1 && 2)
    // 1. The composing range is valid
    // 2. The new string is shorter than the composing range.
    if (_textController.value.isComposingRangeValid) {
      final composingLength = _textController.value.composing.end -
          _textController.value.composing.start;
      if (composingLength > newStr.length) {
        _value = oldValue;
        return;
      }
    }

    // Delete the different part in the old value.
    for (i = 0; i < subOldValue.length - common; ++i) {
      inputModel.inputKey('VK_BACK');
    }

    // Input the new string.
    if (newStr.length > 1) {
      bind.sessionInputString(sessionId: sessionId, value: newStr);
    } else {
      inputChar(newStr);
    }
  }

  void _handleNonIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    if (oldValue.isNotEmpty &&
        newValue.isNotEmpty &&
        oldValue[0] == '1' &&
        newValue[0] != '1') {
      // clipboard
      oldValue = '';
    }
    // This length-only diff assumes the IME appends at the end. If an IME
    // leaves the caret inside paired punctuation, later insertions can replay
    // the closing symbol: "()" -> "(a)" sends ")" instead of "a". This is a
    // client text-diff issue, independent of the host keyboard layout.
    if (newValue.length == oldValue.length) {
      // ?
    } else if (newValue.length < oldValue.length) {
      final char = 'VK_BACK';
      inputModel.inputKey(char);
    } else {
      final content = newValue.substring(oldValue.length);
      if (content.length > 1) {
        if (oldValue != '' &&
            content.length == 2 &&
            (content == '""' ||
                content == '()' ||
                content == '[]' ||
                content == '<>' ||
                content == "{}" ||
                content == '”“' ||
                content == '《》' ||
                content == '（）' ||
                content == '【】')) {
          // can not only input content[0], because when input ], [ are also auo insert, which cause ] never be input
          bind.sessionInputString(sessionId: sessionId, value: content);
          _openKeyboardUnlocked();
          return;
        }
        bind.sessionInputString(sessionId: sessionId, value: content);
      } else {
        inputChar(content);
      }
    }
  }

  // handle mobile virtual keyboard
  void handleSoftKeyboardInput(String newValue) {
    if (!inputModel.keyboardInputAllowed) {
      return;
    }
    if (isIOS) {
      _handleIOSSoftKeyboardInput(newValue);
    } else {
      _handleNonIOSSoftKeyboardInput(newValue);
    }
  }

  void inputChar(String char) {
    if (!inputModel.keyboardInputAllowed) {
      return;
    }
    if (char == '\n') {
      char = 'VK_RETURN';
    } else if (char == ' ') {
      char = 'VK_SPACE';
    }
    inputModel.inputKey(char);
  }

  void openKeyboard() {
    final allowWaylandKeyboard =
        mainGetPeerBoolOptionSync(widget.id, kPeerOptionAllowWaylandKeyboard);
    if (shouldShowWaylandKeyboardPrompt(
      connectionId: sessionId.toString(),
      isWaylandPeer: _shouldGateKeyboardForWayland(),
      allowWaylandKeyboardRemembered: allowWaylandKeyboard,
    )) {
      inputModel.keyboardInputAllowed = false;
      showWaylandKeyboardInputWarningDialog(
        id: widget.id,
        connectionId: sessionId.toString(),
        ffi: gFFI,
        onEnable: () async {
          _openKeyboardUnlocked();
        },
      );
      return;
    }
    _openKeyboardUnlocked();
  }

  void _openKeyboardUnlocked() {
    inputModel.keyboardInputAllowed = true;
    gFFI.invokeMethod("enable_soft_keyboard", true);
    if (isMobile) {
      _resetSessionIme();
    } else {
      _value = initText;
      _textController.text = _value;
    }
    setState(() => _showEdit = false);
    _timer?.cancel();
    _timer = Timer(kMobileDelaySoftKeyboard, () {
      if (!mounted || gFFI.chatModel.inputNode.hasFocus) return;
      // show now, and sleep a while to requestFocus to
      // make sure edit ready, so that keyboard won't show/hide/show/hide happen
      setState(() => _showEdit = true);
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        if (!mounted || !_showEdit || gFFI.chatModel.inputNode.hasFocus) return;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
        _mobileFocusNode.requestFocus();
      });
    });
  }

  Widget _bottomWidget() => _showGestureHelp
      ? getGestureHelp()
      : (!isMobile && _showBar && gFFI.ffiModel.pi.displays.isNotEmpty
          ? getBottomAppBar()
          : Offstage());

  bool get _canSendSessionInput =>
      gFFI.ffiModel.keyboard && !gFFI.ffiModel.viewOnly;

  Future<void> _setSessionInputMode(SessionInputMode mode) async {
    if (!_canSendSessionInput || gFFI.ffiModel.isPeerAndroid) return;
    final model = gFFI.ffiModel;
    final touch = mode == SessionInputMode.touch;
    inputModel.setRelativeMouseMode(false);
    if (model.touchMode != touch) {
      model.toggleTouchMode();
      await bind.mainSetLocalOption(
          key: kOptionTouchMode, value: touch ? 'Y' : 'N');
    }
  }

  void _toggleSessionVirtualMouse() {
    final model = gFFI.ffiModel;
    if (!_canSendSessionInput || !model.touchMode || model.isPeerAndroid) return;
    final mouse = model.virtualMouseMode;
    final show = !mouse.showVirtualMouse;
    mouse.setShowVirtualMouse(show);
    _queueVirtualMouse(() => bind.mainSetLocalOption(
        key: kOptionShowVirtualMouse, value: show ? 'Y' : 'N'));
  }

  void _hideSessionIme() {
    _timer?.cancel();
    _showEdit = false;
    gFFI.invokeMethod('enable_soft_keyboard', false);
    _mobileFocusNode.unfocus();
    _physicalFocusNode.requestFocus();
  }

  void _closeSessionKeyboard() {
    _clearSessionModifiers();
    setState(() {
      _showSessionKeyboard = false;
      _hideSessionIme();
    });
  }

  Set<SessionModifier> get _sessionModifiers => {
        if (inputModel.ctrl) SessionModifier.ctrl,
        if (inputModel.shift) SessionModifier.shift,
        if (inputModel.alt) SessionModifier.alt,
        if (inputModel.command) SessionModifier.meta,
      };

  void _setSessionModifier(SessionModifier modifier, bool selected) {
    switch (modifier) {
      case SessionModifier.ctrl:
        inputModel.ctrl = selected;
      case SessionModifier.shift:
        inputModel.shift = selected;
      case SessionModifier.alt:
        inputModel.alt = selected;
      case SessionModifier.meta:
        inputModel.command = selected;
    }
  }

  void _clearSessionModifiers() {
    final keyboard = HardwareKeyboard.instance;
    inputModel.ctrl = keyboard.isControlPressed;
    inputModel.shift = keyboard.isShiftPressed;
    inputModel.alt = keyboard.isAltPressed;
    inputModel.command = keyboard.isMetaPressed;
  }

  void _sendSessionKey(String key) {
    if (_canSendSessionInput && inputModel.keyboardInputAllowed) {
      if (isMobile && _showEdit) _resetSessionIme();
      inputModel.inputKey(key);
    }
  }

  void _sendSessionShortcut(SessionModifier modifier, String key) {
    final old = _sessionModifiers;
    for (final value in SessionModifier.values) {
      _setSessionModifier(value, value == modifier);
    }
    try {
      _sendSessionKey(key);
    } finally {
      for (final value in SessionModifier.values) {
        _setSessionModifier(value, old.contains(value));
      }
    }
  }

  Future<void> _clickSessionMouse(MouseButtons button, {Offset? nativePoint}) async {
    if (mounted && _canSendSessionInput &&
        await (nativePoint == null ? _ensureVisibleCursor() : _moveToNativePointer(nativePoint))) {
      if (mounted && _canSendSessionInput) {
        if (isMobile && _showEdit) _resetSessionIme();
        await inputModel.tap(button);
      }
    }
  }

  Future<bool> _ensureVisibleCursor({bool recenter = false}) async {
    final cursor = gFFI.cursorModel;
    final remote = gFFI.ffiModel.rect;
    if (remote == null) return false;
    final visible = cursor.getVisibleRect();
    if (!recenter &&
        visible.contains(cursor.offset) &&
        remote.contains(cursor.offset)) {
      return true;
    }
    final intersection = visible.intersect(remote);
    if (intersection.isEmpty) return false;
    final canvas = gFFI.canvasModel;
    final local = (intersection.center - visible.topLeft) * canvas.scale;
    final adjust = canvas.getAdjustY();
    cursor.moveLocal(local.dx, local.dy + adjust, adjust: adjust);
    await cursor.syncCursorPosition();
    return true;
  }

  void _queueVirtualMouse(Future<void> Function() event) {
    _virtualMouseInput =
        _virtualMouseInput.then((_) => event()).catchError((Object error) {
      debugPrint('Virtual mouse input failed: ${error.runtimeType}');
    });
  }

  void _moveSessionMouse(Offset delta) => _queueVirtualMouse(() async {
        if (!mounted || !_canSendSessionInput || !await _ensureVisibleCursor()) {
          return;
        }
        if (!mounted || !_canSendSessionInput) return;
        await gFFI.cursorModel.updatePan(delta, Offset.zero, false);
      });

  void _moveNativePointer(Offset point, Offset pan) {
    final pending = _nativePointerBatch;
    if (pending != null) {
      pending.target = point;
      pending.pan += pan;
      return;
    }
    final batch = _NativePointerBatch(point, pan);
    _nativePointerBatch = batch;
    _queueVirtualMouse(() async {
      if (identical(_nativePointerBatch, batch)) _nativePointerBatch = null;
      await _moveToNativePointer(batch.target, pan: batch.pan);
    });
  }

  Rect _nativePointerViewport(RenderBox box, {bool keyboardTarget = false}) {
    final currentInset = _nativePresentation?.inset ?? 0;
    final keyboardInset =
        keyboardTarget ? _nativeSystemKeyboardTarget ?? currentInset : currentInset;
    final obstruction = keyboardInset > 0 ? keyboardInset + 38 : _nativeKeyboardPanel;
    final keyboardTop = MediaQuery.sizeOf(context).height - obstruction;
    final bottom = obstruction <= 0
        ? box.size.height
        : (keyboardTop - box.localToGlobal(Offset.zero).dy)
            .clamp(0.0, box.size.height)
            .toDouble();
    return Rect.fromLTWH(0, 0, box.size.width, bottom);
  }

  Rect _nativeVideoRect(CanvasModel canvas) => Rect.fromLTWH(
        canvas.x,
        canvas.y + canvas.getAdjustY(),
        canvas.getDisplayWidth() * canvas.scale,
        canvas.getDisplayHeight() * canvas.scale,
      );

  final GlobalKey _androidAwesunOverlayKey = GlobalKey();
  bool get _usesAndroidAwesun => isAndroid && _sessionReady;
  bool get _usesAwesunOverlay => _nativeSessionActive || _usesAndroidAwesun;

  Offset _androidAwesunGlobalPoint(Offset localPoint) {
    final box = _androidAwesunOverlayKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached) {
      return box.localToGlobal(localPoint);
    }
    return localPoint;
  }

  Future<bool> _moveToNativePointer(Offset point, {Offset pan = Offset.zero}) async {
    if (!mounted || !_usesAwesunOverlay || !_canSendSessionInput) return false;
    final box = _sessionViewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final local = box.globalToLocal(point);
    final viewport = _nativePointerViewport(box);
    final canvas = gFFI.canvasModel;
    canvas.panNativeVirtualMouse(pan, viewport, local);
    final target = clampNativePointer(local, _nativeVideoRect(canvas), viewport);
    if (target == null) return false;
    final cursor = gFFI.cursorModel;
    final remote = cursor.getRemotePosInRect(target);
    if (remote == null) return false;
    // Holding against the canvas limit must not resend the same remote pixel.
    if (pan != Offset.zero && remote == cursor.offset) return true;
    cursor.moveLocal(target.dx, target.dy, adjust: canvas.getAdjustY());
    await cursor.syncCursorPosition();
    return true;
  }

  void _holdVirtualMouse({Offset? nativePoint}) => _queueVirtualMouse(() async {
        if (_virtualMouseDown || !mounted || !_canSendSessionInput) return;
        final ready = await (nativePoint == null
            ? _ensureVisibleCursor()
            : _moveToNativePointer(nativePoint));
        if (!ready || !mounted || !_canSendSessionInput) return;
        await inputModel.tapDown(MouseButtons.left);
        _virtualMouseDown = true;
      });

  void _releaseVirtualMouse() {
    final model = inputModel;
    _queueVirtualMouse(() async {
      if (!_virtualMouseDown) return;
      _virtualMouseDown = false;
      await model.releaseVirtualMouseDrag();
    });
  }

  void _sessionAction(SessionAction action) {
    switch (action) {
      case SessionAction.display:
        showOptions(context, widget.id, gFFI.dialogManager);
      case SessionAction.chat:
        if (isAndroid) {
          _openSessionChat();
        } else {
          onPressedTextChat(widget.id);
        }
      case SessionAction.mobile:
        gFFI.dialogManager.toggleMobileActionsOverlay(ffi: gFFI);
      case SessionAction.more:
        showActions(widget.id);
      case SessionAction.disconnect:
        clientClose(sessionId, gFFI);
    }
  }

  Future<void> _openSessionChat() async {
    final support =
        await gFFI.invokeMethod('get_value', 'KEY_IS_SUPPORT_VOICE_CALL');
    if (!mounted) return;
    if (support == true) {
      showChatOptions(widget.id);
    } else {
      onPressedTextChat(widget.id);
    }
  }

  bool get _sessionReady =>
      gFFI.ffiModel.pi.isSet.value && !gFFI.ffiModel.waitForFirstImage.value;

  Future<void> _syncNativeSession() async {
    final requested = _sessionReady;
    if (_nativeSessionRequested == requested) return;
    _nativeSessionRequested = requested;
    if (!requested) {
      _nativePointerBatch = null;
      _releaseVirtualMouse();
      _clearSessionModifiers();
    }
    final revision = ++_nativeSessionRevision;
    final active = await _nativeSession.setActive(requested,
        touchMode: gFFI.ffiModel.touchMode);
    if (mounted &&
        revision == _nativeSessionRevision &&
        active != _nativeSessionActive) {
      setState(() {
        _nativeSessionActive = active;
        if (!active) {
          _nativeVideoTexture = null;
          _nativePointerVisible = false;
        }
      });
      _nativePresentation = null;
      _nativeMouseViewport = null;
      _nativeKeyboardViewport = null;
      _nativeKeyboardPanel = 0;
      _nativeSystemKeyboardTarget = null;
      if (!active) _nativeKeyboardShift.value = 0;
      _lastNativePerformance = const {};
      _syncNativePresentation();
      await gFFI.canvasModel.setMobileHeightFit(active);
      if (active && mounted) {
        if (_nativeFixedFps) await _nativeSession.configureVideoTexture(true);
        _syncNativePerformance();
      }
    }
  }

  void _syncNativePresentation() {
    if (!mounted || !_nativeSessionActive) return;
    final next = (
      obscured: gFFI.dialogManager.openDialog.value ||
          gFFI.chatModel.chatWindowOpen.value ||
          ModalRoute.isCurrentOf(context) == false,
      inset: MediaQuery.viewInsetsOf(context).bottom,
    );
    if (_nativePresentation == next) return;
    _nativePresentation = next;
    _scheduleSessionViewportUpdate();
    unawaited(_nativeSession.updatePresentation(
        obscured: next.obscured, keyboardInset: next.inset));
  }

  Future<Object?> _nativeCommand(
      String id, Map<Object?, Object?> arguments) async {
    if (!mounted || !_sessionReady) return null;
    final model = gFFI.ffiModel;
    switch (id) {
      case 'interruptCanvasPan':
        _canvasDrag.interrupt();
        _nativePointerBatch?.pan = Offset.zero;
        return null;
      case 'panCanvasBy':
        final canvas = gFFI.canvasModel;
        if (!_nativeSessionActive || !_canSendSessionInput || canvas.locked) {
          return null;
        }
        if (arguments case {'x': num x, 'y': num y, 'dx': num dx, 'dy': num dy}) {
          final tip = Offset(x.toDouble(), y.toDouble());
          final delta = Offset(dx.toDouble(), dy.toDouble());
          final box = _sessionViewportKey.currentContext?.findRenderObject();
          if (tip.isFinite && delta.isFinite && box is RenderBox &&
              box.attached && box.hasSize) {
            // A touch delta has already happened; a following lift must not discard it.
            final before = Offset(canvas.x, canvas.y);
            canvas.panNativeVirtualMouse(
                delta, _nativePointerViewport(box), box.globalToLocal(tip));
            if (before != Offset(canvas.x, canvas.y)) {
              _moveNativePointer(tip, Offset.zero);
            }
          }
        }
        return null;
      case 'menu':
        return _nativeMenu(model);
      case 'action':
        final index = arguments['index'];
        if (index is int && index >= 0 && index < _nativeActions.length) {
          final action = _nativeActions[index];
          _nativeActions = const [];
          action();
        }
      case 'display':
        return _nativeDisplayMenu();
      case 'performance':
        await _setNativePerformance(arguments['enabled'] == true);
      case 'performanceTarget':
        final fps = arguments['fps'];
        if (fps is int && const [30, 60, 90, 120].contains(fps)) {
          _nativePerformanceTarget = fps;
          if (_nativeFixedFps) {
            await bind.sessionSetCustomFps(sessionId: sessionId, fps: fps);
          }
          _syncNativePerformance();
        }
      case 'displayAction':
        final index = arguments['index'];
        if (index is int && index >= 0 && index < _nativeDisplayActions.length) {
          await _nativeDisplayActions[index]();
        }
      case 'chat':
        _sessionAction(SessionAction.chat);
      case 'systemKeyboardTarget':
        final inset = arguments['inset'];
        if (inset is num && inset.isFinite && inset >= 0 &&
            _nativeSystemKeyboardTarget != inset) {
          _nativeSystemKeyboardTarget = inset.toDouble();
          _scheduleSessionViewportUpdate();
        }
      case 'keyboardPanelHeight':
        final height = arguments['height'];
        if (height is num && height.isFinite && height >= 0 &&
            _nativeKeyboardPanel != height) {
          _nativeKeyboardPanel = height.toDouble();
          _scheduleSessionViewportUpdate();
        }
      case 'keyboard':
        if (arguments['visible'] == false) {
          setState(_hideSessionIme);
        } else if (_canSendSessionInput) {
          openKeyboard();
        }
      case 'mode':
        if (_canSendSessionInput && !model.isPeerAndroid) {
          await _setSessionInputMode(arguments['touch'] == true
              ? SessionInputMode.touch
              : SessionInputMode.pointer);
        }
        return model.touchMode;
      case 'modifier':
        final name = arguments['name'];
        for (final modifier in SessionModifier.values) {
          if (modifier.name == name &&
              (_canSendSessionInput || arguments['down'] == false)) {
            _setSessionModifier(modifier, arguments['down'] == true);
          }
        }
      case 'shortcut':
        final key = arguments['key'];
        if (!_canSendSessionInput || key is! String) return null;
        if (key == 'secure-attention') {
          final pi = model.pi;
          if (pi.sasEnabled || pi.platform == kPeerPlatformLinux) {
            await bind.sessionCtrlAltDel(sessionId: sessionId);
          }
          return null;
        }
        final modifiers = arguments['modifiers'];
        if (modifiers is List) {
          final previous = _sessionModifiers;
          for (final modifier in SessionModifier.values) {
            _setSessionModifier(modifier, modifiers.contains(modifier.name));
          }
          try {
            _sendSessionKey(key);
          } finally {
            for (final modifier in SessionModifier.values) {
              _setSessionModifier(modifier, previous.contains(modifier));
            }
          }
        } else {
          _sendSessionKey(key);
        }
      case 'releaseModifiers':
        _clearSessionModifiers();
      case 'lock':
        gFFI.canvasModel.setLocked(arguments['locked'] == true);
        return gFFI.canvasModel.locked;
      case 'sound':
        if (model.permissions['audio'] != false) {
          const option = 'disable-audio';
          await bind.sessionToggleOption(sessionId: sessionId, value: option);
          return !_nativeOption(option);
        }
      case 'screen':
        final index = arguments['index'];
        if (index is int && _nativeCanSwitchDisplay(model) &&
            index >= 0 && index < model.pi.displays.length &&
            index != model.pi.currentDisplay) {
          openMonitorInTheSameTab(index, gFFI, model.pi);
        }
      case 'shot':
        return _saveNativeScreenshot();
      case 'quality':
        await bind.sessionToggleOption(
            sessionId: sessionId, value: 'show-quality-monitor');
        gFFI.qualityMonitorModel.checkShowQualityMonitor(sessionId);
    }
    return null;
  }

  Map<String, Object?> _nativeMenu(FfiModel model) {
    final actions = <VoidCallback>[];
    final titles = <String>[];
    void add(String title, VoidCallback action) {
      titles.add(title);
      actions.add(action);
    }

    String? label(Widget child) => switch (child) {
          Text(:final data) => data,
          Row(:final children) when children.isNotEmpty => label(children.first),
          _ => null,
        };

    for (final menu in [
      ..._getMobileActionMenus(),
      ...toolbarControls(context, widget.id, gFFI),
    ]) {
      final command = menu.onPressed;
      final blocked = BlockInputState.find(widget.id).value;
      final title = menu.actionId == kShortcutActionToggleBlockInput
          ? translate(blocked ? 'Unblock user input' : 'Block user input')
          : label(menu.child);
      if (command != null && title != null) add(title, command);
      if (command != null && title == translate('OS Password')) {
        add('${translate('Edit')} $title',
            () => handleOsPasswordEditIcon(sessionId, gFFI.dialogManager));
      }
    }
    if (_canSendSessionInput && !model.isPeerAndroid) {
      add(translate('Center cursor'), () => _queueVirtualMouse(() async {
            if (mounted && _canSendSessionInput) {
              await _ensureVisibleCursor(recenter: true);
            }
          }));
    }
    if (gFFI.qualityMonitorModel.udpReports.isNotEmpty) {
      add('UDP · ${translate("Remote device")}', () => showPeerUdpReport(context, gFFI.qualityMonitorModel));
    }
    if (recordIosP2pDiagnostics) {
      add(translate('Copy P2P diagnostics'), _copyP2pDiagnostics);
    }
    _nativeActions = actions;
    return {
      'actions': titles,
      'canInput': _canSendSessionInput,
      'canSwitchMode': _canSendSessionInput && !model.isPeerAndroid,
      'locked': gFFI.canvasModel.locked,
      'touch': model.touchMode,
      'sound': !_nativeOption('disable-audio'),
      'canSound': model.permissions['audio'] != false,
      'screenshot': _nativeVideoTexture != null || gFFI.imageModel.image != null,
      'displays': _nativeCanSwitchDisplay(model) ? model.pi.displays.length : 0,
      'selectedDisplay': model.pi.currentDisplay,
      'quality': _nativeOption('show-quality-monitor'),
    };
  }

  bool _nativeOption(String option) =>
      bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: option);

  bool _nativeCanSwitchDisplay(FfiModel model) {
    final state = PrivacyModeState.find(widget.id);
    return model.pi.displays.length > 1 &&
        model.pi.currentDisplay != kAllDisplayValue &&
        (state.isEmpty || allowDisplaySwitchInPrivacyMode(model.pi, state.value));
  }

  void _syncNativePerformance() {
    if (!mounted || !_nativeSessionActive) return;
    final stats = gFFI.qualityMonitorModel.data;
    final valid = gFFI.ffiModel.pi.features.fixedScreenFps;
    final enabled = _nativeFixedFps;
    final host = stats.fixedScreenFps;
    final next = <String, Object?>{
      'supported': valid,
      'enabled': enabled,
      'target': _nativePerformanceTarget,
      'effective': host,
      'gpuEncode': stats.gpuTextureEncode,
      'gpuDecode': _nativeVideoTexture != null,
      'fps': stats.fps,
    };
    if (mapEquals(next, _lastNativePerformance)) return;
    _lastNativePerformance = next;
    unawaited(_nativeSession.updatePerformance(next));
  }

  Future<void> _setNativePerformance(bool enabled) async {
    if (_nativePerformanceBusy || enabled == _nativeFixedFps ||
        !gFFI.ffiModel.pi.features.fixedScreenFps) return;
    _nativePerformanceBusy = true;
    try {
      if (enabled) await _nativeSession.configureVideoTexture(true);
      if (!mounted) return;
      await bind.sessionToggleOption(sessionId: sessionId, value: 'fixed-screen-fps');
      _nativeFixedFps = _nativeOption('fixed-screen-fps');
      if (_nativeFixedFps) {
        if (_nativePerformanceTarget != 60) {
          await bind.sessionSetCustomFps(sessionId: sessionId, fps: _nativePerformanceTarget);
        }
      } else {
        await _nativeSession.configureVideoTexture(false);
        if (mounted) setState(() => _nativeVideoTexture = null);
      }
      _syncNativePerformance();
    } finally {
      _nativePerformanceBusy = false;
    }
  }

  Future<List<Map<String, Object?>>> _nativeDisplayMenu() async {
    final choices = <Map<String, Object?>>[];
    final commands = <Future<void> Function()>[];
    final canvas = gFFI.canvasModel;
    void add(String group, String name, bool selected,
        Future<void> Function() apply) {
      choices.add({
        'index': commands.length,
        'group': group,
        'title': name,
        'selected': selected,
      });
      commands.add(apply);
    }

    add('画面比例', '高度撑满', canvas.mobileHeightFit,
        () => canvas.setMobileHeightFit(true));
    final scales = await toolbarViewStyle(context, widget.id, gFFI);
    if (!mounted) return const [];
    final qualities = await toolbarImageQuality(context, widget.id, gFFI);
    if (!mounted) return const [];
    final codecs = await toolbarCodec(context, widget.id, gFFI);
    if (!mounted) return const [];
    final remoteCursor = await toolbarCursor(context, widget.id, gFFI);
    if (!mounted) return const [];
    final toggles = await toolbarDisplayToggle(context, widget.id, gFFI);
    if (!mounted) return const [];
    final scale = await getSessionCustomScalePercent(sessionId);
    if (!mounted) return const [];
    for (final item in scales) {
      if (item.value == kRemoteViewStyleCustom) continue;
      final name = item.value == kRemoteViewStyleAdaptive ? '完整画面' : '原始比例';
      add('画面比例', name,
          !canvas.mobileHeightFit && item.value == item.groupValue, () async {
        await canvas.setMobileHeightFit(false);
        await bind.sessionSetViewStyle(sessionId: sessionId, value: item.value);
        await canvas.updateViewStyle();
      });
    }
    for (final group in [('画质', qualities), ('编码', codecs)]) {
      for (final item in group.$2) {
        final title = item.child;
        if (title is! Text || title.data == null || item.onChanged == null) {
          continue;
        }
        if (group.$1 == '画质' && item.value == kRemoteImageQualityCustom) continue;
        add(group.$1, title.data!, item.value == item.groupValue, () async {
          item.onChanged?.call(item.value);
        });
      }
    }
    for (final item in [...remoteCursor, ...toggles]) {
      final title = item.child;
      if (title is! Text || title.data == null || item.onChanged == null) {
        continue;
      }
      add('显示选项', title.data!, item.value, () async {
        item.onChanged?.call(!item.value);
      });
    }
    final peer = gFFI.ffiModel.pi;
    final viewMode = scales.isEmpty ? null : scales.first.groupValue;
    for (final percent in [75, 100, 125, 150, 200]) {
      add('自定义缩放', '$percent%', !canvas.mobileHeightFit &&
          viewMode == kRemoteViewStyleCustom && scale == percent, () async {
        await canvas.setMobileHeightFit(false);
        await bind.sessionSetFlutterOption(sessionId: sessionId,
            k: kCustomScalePercentKey, v: percent.toString());
        await bind.sessionSetViewStyle(sessionId: sessionId, value: kRemoteViewStyleCustom);
        await canvas.updateViewStyle();
      });
    }

    final previousQuality = await bind.sessionGetOption(sessionId: sessionId, arg: 'custom-image-quality');
    if (!mounted) return const [];
    final currentQuality = qualities.isEmpty ? null : qualities.first.groupValue;
    for (final percent in [40, 60, 80, 100]) {
      add('自定义画质', '$percent%', currentQuality == kRemoteImageQualityCustom &&
          int.tryParse(previousQuality ?? '') == percent, () async {
        await bind.sessionSetImageQuality(sessionId: sessionId, value: kRemoteImageQualityCustom);
        await bind.sessionSetCustomImageQuality(sessionId: sessionId, value: percent);
      });
    }

    final display = peer.tryGetDisplayIfNotAllDisplay(display: peer.currentDisplay);
    final displayIndex = peer.currentDisplay;
    if (_canSendSessionInput && display != null && peer.resolutions.length > 1) {
      for (final resolution in peer.resolutions) {
        final width = resolution.width;
        final height = resolution.height;
        add('远端分辨率', '$width × $height',
            display.width == width && display.height == height, () async {
          if (!_canSendSessionInput || peer.currentDisplay != displayIndex ||
              !peer.resolutions.any((mode) => mode.width == width && mode.height == height)) {
            return;
          }
          await bind.sessionChangeResolution(sessionId: sessionId,
              display: displayIndex, width: width, height: height);
        });
      }
    }

    final privacy = PrivacyModeState.find(widget.id);
    if (gFFI.ffiModel.pi.features.privacyMode && _canSendSessionInput ||
        privacy.isNotEmpty) {
      for (final item in toolbarPrivacyMode(privacy, context, widget.id, gFFI)) {
        final title = item.child;
        if (title is Text && title.data != null && item.onChanged != null) {
          add('显示选项', title.data!, item.value, () async {
            item.onChanged?.call(!item.value);
          });
        }
      }
    }

    if (showVirtualDisplayMenu(gFFI) && privacy.isEmpty) {
      if (peer.isRustDeskIdd) {
        for (var index = 1; index <= kMaxVirtualDisplayCount; index++) {
          final present = peer.RustDeskVirtualDisplays.contains(index);
          add('虚拟显示器', '显示器 $index', present, () async {
            if (!PrivacyModeState.find(widget.id).isNotEmpty) {
              await bind.sessionToggleVirtualDisplay(sessionId: sessionId,
                  index: index, on: !peer.RustDeskVirtualDisplays.contains(index));
            }
          });
        }
      } else if (peer.isAmyuniIdd) {
        for (final enabled in [true, false]) {
          add('虚拟显示器', enabled ? '添加' : '移除', false, () async {
            if (privacy.isEmpty && (enabled ? peer.amyuniVirtualDisplayCount < 4 : peer.amyuniVirtualDisplayCount > 0)) {
              await bind.sessionToggleVirtualDisplay(sessionId: sessionId, index: 0, on: enabled);
            }
          });
        }
      }
      add('虚拟显示器', '移除全部', false, () async {
        if (privacy.isEmpty) {
          await bind.sessionToggleVirtualDisplay(sessionId: sessionId,
              index: kAllVirtualDisplay, on: false);
        }
      });
    }
    _nativeDisplayActions = commands;
    _syncNativePerformance();
    return choices;
  }

  Future<String> _saveNativeScreenshot() async {
    if (_savingNativeScreenshot) return 'pending';
    final nativeTexture = _nativeVideoTexture;
    final frame = nativeTexture == null ? gFFI.imageModel.image?.clone() : null;
    if (frame == null && nativeTexture == null) return 'noFrame';
    _savingNativeScreenshot = true;
    try {
      if (frame == null) return await _nativeSession.saveTexturePhoto();
      final png = await frame.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return 'encodeFailed';
      return await _nativeSession.savePhoto(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
    } catch (error) {
      debugPrint('Remote frame screenshot failed: ${error.runtimeType}');
      return 'saveFailed';
    } finally {
      frame?.dispose();
      _savingNativeScreenshot = false;
    }
  }

  void _openSessionKeyboard() {
    setState(() => _showSessionKeyboard = true);
    openKeyboard();
  }

  Widget _sessionDock() {
    final model = context.watch<FfiModel>();
    return Obx(() {
      if (!_sessionReady || (_showSessionKeyboard && _canSendSessionInput)) {
        return const SizedBox.shrink();
      }
      if (_showGestureHelp) {
        return SessionControlsSurface(
          child: IconButton(
            tooltip: translate('Close'),
            color: sessionControlInk,
            onPressed: () => setState(() => _showGestureHelp = false),
            icon: const Icon(Icons.close),
          ),
        );
      }
      return ListenableBuilder(
        listenable: model.virtualMouseMode,
        builder: (context, child) => SessionControlsDock(
          mode:
              model.touchMode ? SessionInputMode.touch : SessionInputMode.pointer,
          showInputModes: _canSendSessionInput && !model.isPeerAndroid,
          onMode: _setSessionInputMode,
          virtualMouseEnabled: model.virtualMouseMode.showVirtualMouse,
          onToggleVirtualMouse:
              _canSendSessionInput && !model.isPeerAndroid && model.touchMode
                  ? _toggleSessionVirtualMouse
                  : null,
          onGestureSettings: () => setState(() => _showGestureHelp = true),
          onKeyboard: _canSendSessionInput ? _openSessionKeyboard : null,
          onCenterCursor: _canSendSessionInput && !model.isPeerAndroid
              ? () => _queueVirtualMouse(() async {
                    if (mounted && _canSendSessionInput) {
                      await _ensureVisibleCursor(recenter: true);
                    }
                  })
              : null,
          actions: [
            SessionAction.display,
            SessionAction.chat,
            if (_canSendSessionInput && model.isPeerAndroid)
              SessionAction.mobile,
            SessionAction.more,
            SessionAction.disconnect,
          ],
          onAction: _sessionAction,
        ),
      );
    });
  }

  void _scheduleSessionViewportUpdate() {
    if (_viewportUpdateScheduled) return;
    _viewportUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportUpdateScheduled = false;
      if (!mounted) return;
      Rect? bounds(GlobalKey key) {
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) return null;
        return box.localToGlobal(Offset.zero) & box.size;
      }

      final canvas = bounds(_sessionViewportKey);
      if (canvas == null) return;
      if (_nativeSessionActive) {
        final box = _sessionViewportKey.currentContext?.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          _updateNativeKeyboardViewport(box);
        }
        return;
      }
      final keyboard = bounds(_sessionKeyboardKey);
      gFFI.canvasModel.updateMobileSessionViewport(
        sessionVisibleViewport(canvas, keyboard),
        keyboardOpen: keyboard != null,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _updateNativeKeyboardViewport(RenderBox box) {
    final viewport = (full: box.size, visible: _nativePointerViewport(box, keyboardTarget: true).height);
    if (_nativeKeyboardViewport == viewport) return;
    _nativeKeyboardViewport = viewport;
    final canvas = gFFI.canvasModel;
    canvas.updateMobileSessionViewport(viewport.full, keyboardOpen: false);
    final shift = nativeKeyboardLift(viewport.full.height, viewport.visible);
    if (MediaQuery.disableAnimationsOf(context)) {
      _nativeKeyboardShift.value = shift;
    } else {
      _nativeKeyboardShift.animateTo(shift,
          duration: const Duration(milliseconds: 220), curve: Curves.linear);
    }
    _scheduleNativeMouseViewport();
  }

  Widget _sessionInputOverlays(bool imeVisible) {
    final model = context.watch<FfiModel>();
    return Obx(() {
      _scheduleSessionViewportUpdate();
      if (!_sessionReady) {
        return const SizedBox.shrink();
      }
      if (_showSessionKeyboard && _canSendSessionInput) {
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: constraints.maxHeight * (imeVisible ? .60 : .65),
                ),
                child: NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (_) {
                    _scheduleSessionViewportUpdate();
                    return false;
                  },
                  child: SizeChangedLayoutNotifier(
                    key: _sessionKeyboardKey,
                    child: SessionKeyboard(
                      compact: _showEdit,
                      isMac: model.pi.platform == kPeerPlatformMacOS,
                      showMouseButtons: !model.isPeerAndroid,
                      enabled: inputModel.keyboardInputAllowed,
                      modifiers: _sessionModifiers,
                      onModifier: (modifier) => setState(() =>
                          _setSessionModifier(
                              modifier, !_sessionModifiers.contains(modifier))),
                      onKey: _sendSessionKey,
                      onMouse: _clickSessionMouse,
                      onShortcut: _sendSessionShortcut,
                      onTextInput: _showEdit
                          ? () => setState(_hideSessionIme)
                          : openKeyboard,
                      onClose: _closeSessionKeyboard,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (_usesAndroidAwesun && !_showGestureHelp) {
        return AnimatedBuilder(
          animation: Listenable.merge([
            gFFI.canvasModel,
            gFFI.qualityMonitorModel,
          ]),
          builder: (context, _) {
            final canvas = gFFI.canvasModel;
            final peer = model.pi;
            final soundMuted = bind.sessionGetToggleOptionSync(
                sessionId: sessionId, arg: 'disable-audio');
            return AwesunFlutterOverlay(
              key: _androidAwesunOverlayKey,
              touchMode: model.touchMode,
              canInput: _canSendSessionInput && !model.isPeerAndroid,
              canSwitchMode: _canSendSessionInput && !model.isPeerAndroid,
              displayLocked: canvas.locked,
              soundOn: !soundMuted,
              qualityVisible: gFFI.qualityMonitorModel.show,
              displayCount: peer.displays.length,
              translateLabel: translate,
              onMovePointer: (local) => _moveNativePointer(
                _androidAwesunGlobalPoint(local),
                Offset.zero,
              ),
              onLeftClick: (local) {
                final pt = _androidAwesunGlobalPoint(local);
                _queueVirtualMouse(
                    () => _clickSessionMouse(MouseButtons.left, nativePoint: pt));
              },
              onRightClick: (local) {
                final pt = _androidAwesunGlobalPoint(local);
                _queueVirtualMouse(
                    () => _clickSessionMouse(MouseButtons.right, nativePoint: pt));
              },
              onMiddleClick: (local) {
                final pt = _androidAwesunGlobalPoint(local);
                _queueVirtualMouse(
                    () => _clickSessionMouse(MouseButtons.wheel, nativePoint: pt));
              },
              onLeftDragStart: (local) => _holdVirtualMouse(
                nativePoint: _androidAwesunGlobalPoint(local),
              ),
              onLeftDragEnd: _releaseVirtualMouse,
              onScroll: (steps, local) {
                final pt = _androidAwesunGlobalPoint(local);
                _queueVirtualMouse(() async {
                  if (await _moveToNativePointer(pt) &&
                      mounted &&
                      _canSendSessionInput) {
                    await inputModel.scroll(steps);
                  }
                });
              },
              onToggleLock: () =>
                  setState(() => canvas.setLocked(!canvas.locked)),
              onSelectTouchMode: (touch) => unawaited(_setSessionInputMode(
                  touch ? SessionInputMode.touch : SessionInputMode.pointer)),
              onOpenSystemKeyboard: openKeyboard,
              onOpenVirtualKeyboard: _openSessionKeyboard,
              onOpenDisplaySettings: () =>
                  _sessionAction(SessionAction.display),
              onToggleQuality: () {
                unawaited(bind
                    .sessionToggleOption(
                        sessionId: sessionId, value: 'show-quality-monitor')
                    .then((_) => gFFI.qualityMonitorModel
                        .checkShowQualityMonitor(sessionId)));
              },
              onToggleSound: () {
                unawaited(bind
                    .sessionToggleOption(
                        sessionId: sessionId, value: 'disable-audio')
                    .then((_) {
                  if (mounted) setState(() {});
                }));
              },
              onSwitchDisplay: peer.displays.length > 1
                  ? () {
                      final next =
                          (peer.currentDisplay + 1) % peer.displays.length;
                      openMonitorInTheSameTab(next, gFFI, peer);
                    }
                  : null,
              onOpenChat: () => _sessionAction(SessionAction.chat),
              onOpenMore: () => _sessionAction(SessionAction.more),
              onDisconnect: () => _sessionAction(SessionAction.disconnect),
              onPointerVisibilityChanged: (visible) {
                if (mounted && _nativePointerVisible != visible) {
                  setState(() => _nativePointerVisible = visible);
                }
              },
            );
          },
        );
      }
      if (!_canSendSessionInput ||
          _showGestureHelp ||
          model.isPeerAndroid ||
          !model.touchMode) {
        return const SizedBox.shrink();
      }
      return ListenableBuilder(
        listenable: model.virtualMouseMode,
        builder: (context, child) {
          if (!model.virtualMouseMode.showVirtualMouse) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            minimum: const EdgeInsets.only(bottom: 56),
            child: SessionTouchpad(
              scale: model.virtualMouseMode.virtualMouseScale,
              onMove: _moveSessionMouse,
              onLeftClick: () => _queueVirtualMouse(
                  () => _clickSessionMouse(MouseButtons.left)),
              onRightClick: () => _queueVirtualMouse(
                  () => _clickSessionMouse(MouseButtons.right)),
              onMiddleClick: () => _queueVirtualMouse(
                  () => _clickSessionMouse(MouseButtons.wheel)),
              onDragStart: _holdVirtualMouse,
              onDragEnd: _releaseVirtualMouse,
              onScroll: (steps) {
                if (_canSendSessionInput) unawaited(inputModel.scroll(steps));
              },
              onZoom: (ratio) {
                final canvas = gFFI.canvasModel;
                if (!canvas.locked) {
                  canvas.updateScale(
                      ratio, canvas.getSize().center(Offset.zero));
                }
              },
            ),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardIsVisible =
        keyboardVisibilityController.isVisible && _showEdit;
    final showActionButton = !_showBar || keyboardIsVisible || _showGestureHelp;
    if (_nativeSessionActive) _syncNativePresentation();

    return WillPopScope(
      onWillPop: () async {
        if (isMobile && _showSessionKeyboard) {
          _closeSessionKeyboard();
          return false;
        }
        if (isMobile && _showGestureHelp) {
          setState(() => _showGestureHelp = false);
          return false;
        }
        clientClose(sessionId, gFFI);
        return false;
      },
      child: Scaffold(
          resizeToAvoidBottomInset: !_nativeSessionActive,
          backgroundColor: isMobile ? Colors.black : null,
          // workaround for https://github.com/rustdesk/rustdesk/issues/3131
          floatingActionButtonLocation: keyboardIsVisible
              ? FABLocation(FloatingActionButtonLocation.endFloat, 0, -35)
              : null,
          floatingActionButton: isMobile
              ? (isAndroid ||
                      _nativeSessionActive ||
                      (keyboardVisibilityController.isVisible && !_showEdit)
                  ? null
                  : _sessionDock())
              : !showActionButton
                  ? null
                  : FloatingActionButton(
                      mini: !keyboardIsVisible,
                      child: Icon(
                        (keyboardIsVisible || _showGestureHelp)
                            ? Icons.expand_more
                            : Icons.expand_less,
                        color: Colors.white,
                      ),
                      backgroundColor: MyTheme.accent,
                      onPressed: () {
                        setState(() {
                          if (keyboardIsVisible) {
                            _showEdit = false;
                            gFFI.invokeMethod("enable_soft_keyboard", false);
                            _mobileFocusNode.unfocus();
                            _physicalFocusNode.requestFocus();
                          } else if (_showGestureHelp) {
                            _showGestureHelp = false;
                          } else {
                            _showBar = !_showBar;
                          }
                        });
                      }),
          bottomNavigationBar: Obx(() => Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  gFFI.ffiModel.pi.isSet.isTrue &&
                          gFFI.ffiModel.waitForFirstImage.isTrue
                      ? emptyOverlay(MyTheme.canvasColor)
                      : () {
                          gFFI.ffiModel.tryShowAndroidActionsOverlay();
                          return Offstage();
                        }(),
                  _bottomWidget(),
                  gFFI.ffiModel.pi.isSet.isFalse
                      ? emptyOverlay(MyTheme.canvasColor)
                      : Offstage(),
                ],
              )),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Obx(() => getRawPointerAndKeyBody(
                  Overlay.wrap(child: _buildSessionCanvas()))),
              if (isMobile && _showEdit && _canSendSessionIme)
                _sessionImeEditor(),
              if (isMobile && !_nativeSessionActive)
                _sessionInputOverlays(keyboardIsVisible),
            ],
          )),
    );
  }

  Widget _buildSessionCanvas() {
    if (isWebDesktop) {
      return Container(
          color: kColorCanvas, child: getBodyForDesktopWithListener());
    }
    final viewport = OrientationBuilder(builder: (ctx, orientation) {
      if (_currentOrientation != orientation) {
        _currentOrientation = orientation;
        Timer(const Duration(milliseconds: 200), () {
          if (!mounted || _currentOrientation != orientation) return;
          gFFI.dialogManager.resetMobileActionsOverlay(ffi: gFFI);
          gFFI.canvasModel.updateViewStyle();
        });
      }
      return Obx(() => inputModel.isPhysicalMouse.value
          ? getBodyForMobile()
          : RawTouchGestureDetectorRegion(
              child: getBodyForMobile(),
              ffi: gFFI,
              awesunCanvas: _usesAwesunOverlay,
              canvasDrag: _usesAwesunOverlay && !gFFI.ffiModel.isPeerMobile
                  ? _canvasDrag
                  : null,
            ));
    });
    final canvas = ColoredBox(
      color: isMobile ? Colors.black : kColorCanvas,
      child: SafeArea(
        maintainBottomViewPadding: _nativeSessionActive,
        child: isMobile
            ? LayoutBuilder(builder: (context, constraints) {
                _scheduleSessionViewportUpdate();
                return SizedBox.expand(
                    key: _sessionViewportKey, child: viewport);
              })
            : viewport,
      ),
    );
    // Selecting a new remote caret invalidates the local committed suffix.
    if (isMobile) {
      return Listener(
        onPointerDown: (_) {
          if (_showEdit) _resetSessionIme();
        },
        child: canvas,
      );
    }
    return canvas;
  }

  bool _handleLocalKeyEvent(KeyEvent event) => handleMobileLocalKeyEvent(event,
      remoteFocused: _physicalFocusNode.hasPrimaryFocus ||
          (isMobile && _mobileFocusNode.hasPrimaryFocus),
      inputModel: inputModel);

  Widget _sessionImeEditor() => Positioned(
        width: 0,
        height: 0,
        top: 0,
        left: 0,
        child: TextFormField(
          autofocus: true,
          focusNode: _mobileFocusNode,
          controller: _textController,
          autocorrect: false,
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          enableIMEPersonalizedLearning: false,
        ),
      );

  Widget getRawPointerAndKeyBody(Widget child) {
    final ffiModel = Provider.of<FfiModel>(context);
    return RawPointerMouseRegion(
      cursor: ffiModel.keyboard ? SystemMouseCursors.none : MouseCursor.defer,
      inputModel: inputModel,
      // Disable RawKeyFocusScope before the connecting is established.
      // The "Delete" key on the soft keyboard may be grabbed when inputting the password dialog.
      child: gFFI.ffiModel.pi.isSet.isTrue
          ? RawKeyFocusScope(
              focusNode: _physicalFocusNode,
              inputModel: inputModel,
              child: child)
          : child,
    );
  }

  Widget getBottomAppBar() {
    final ffiModel = Provider.of<FfiModel>(context);
    return BottomAppBar(
      elevation: 10,
      color: MyTheme.accent,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
              children: <Widget>[
                    IconButton(
                      color: Colors.white,
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        clientClose(sessionId, gFFI);
                      },
                    ),
                    IconButton(
                      color: Colors.white,
                      icon: Icon(Icons.tv),
                      onPressed: () {
                        setState(() => _showEdit = false);
                        showOptions(context, widget.id, gFFI.dialogManager);
                      },
                    )
                  ] +
                  (isWebDesktop || ffiModel.viewOnly || !ffiModel.keyboard
                      ? []
                      : gFFI.ffiModel.isPeerAndroid
                          ? [
                              IconButton(
                                  color: Colors.white,
                                  icon: Icon(Icons.keyboard),
                                  onPressed: openKeyboard),
                              IconButton(
                                color: Colors.white,
                                icon: const Icon(Icons.build),
                                onPressed: () => gFFI.dialogManager
                                    .toggleMobileActionsOverlay(ffi: gFFI),
                              )
                            ]
                          : [
                              IconButton(
                                  color: Colors.white,
                                  icon: Icon(Icons.keyboard),
                                  onPressed: openKeyboard),
                              IconButton(
                                color: Colors.white,
                                icon: Icon(gFFI.ffiModel.touchMode
                                    ? Icons.touch_app
                                    : Icons.mouse),
                                onPressed: () => setState(
                                    () => _showGestureHelp = !_showGestureHelp),
                              ),
                            ]) +
                  (isWeb
                      ? []
                      : <Widget>[
                          futureBuilder(
                              future: gFFI.invokeMethod(
                                  "get_value", "KEY_IS_SUPPORT_VOICE_CALL"),
                              hasData: (isSupportVoiceCall) => IconButton(
                                    color: Colors.white,
                                    icon: isAndroid && isSupportVoiceCall
                                        ? SvgPicture.asset('assets/chat.svg',
                                            colorFilter: ColorFilter.mode(
                                                Colors.white, BlendMode.srcIn))
                                        : Icon(Icons.message),
                                    onPressed: () =>
                                        isAndroid && isSupportVoiceCall
                                            ? showChatOptions(widget.id)
                                            : onPressedTextChat(widget.id),
                                  ))
                        ]) +
                  [
                    IconButton(
                      color: Colors.white,
                      icon: Icon(Icons.more_vert),
                      onPressed: () {
                        setState(() => _showEdit = false);
                        showActions(widget.id);
                      },
                    ),
                  ]),
          Obx(() => IconButton(
                color: Colors.white,
                icon: Icon(Icons.expand_more),
                onPressed: gFFI.ffiModel.waitForFirstImage.isTrue
                    ? null
                    : () {
                        setState(() => _showBar = !_showBar);
                      },
              )),
        ],
      ),
    );
  }

  bool get showCursorPaint =>
      !gFFI.ffiModel.isPeerAndroid &&
      !gFFI.canvasModel.cursorEmbedded &&
      !gFFI.inputModel.relativeMouseMode.value;

  void _scheduleNativeMouseViewport() {
    if (!_nativeSessionActive || _nativeMouseViewportScheduled) return;
    _nativeMouseViewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nativeMouseViewportScheduled = false;
      if (!mounted || !_nativeSessionActive) return;
      final box = _sessionViewportKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final canvas = gFFI.canvasModel;
      final local = _nativeVideoRect(canvas).intersect(_nativePointerViewport(box));
      if (local.isEmpty) return;
      final global = box.localToGlobal(local.topLeft) & local.size;
      if (_nativeMouseViewport == global) return;
      _nativeMouseViewport = global;
      unawaited(_nativeSession.setMouseViewport(global));
    });
  }

  Widget getBodyForMobile() {
    return Container(
        color: isMobile ? Colors.black : MyTheme.canvasColor,
        child: Stack(children: () {
          final paints = [
            if (_nativeSessionActive)
              Consumer<CanvasModel>(builder: (context, canvas, _) {
                _scheduleNativeMouseViewport();
                return const SizedBox.expand();
              }),
            if (_nativeVideoTexture != null)
              Consumer<CanvasModel>(builder: (context, canvas, _) {
                final texture = _nativeVideoTexture;
                if (texture == null) return const SizedBox.shrink();
                return Positioned(
                  left: canvas.x,
                  top: canvas.y + canvas.getAdjustY(),
                  width: canvas.getDisplayWidth() * canvas.scale,
                  height: canvas.getDisplayHeight() * canvas.scale,
                  child: Texture(textureId: texture, filterQuality: FilterQuality.low),
                );
              })
            else
              ImagePaint(ffiModel: gFFI.ffiModel),
            if (isMobile)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: gFFI.qualityMonitorModel,
                  builder: (context, _) {
                    final model = gFFI.qualityMonitorModel;
                    final data = model.data;
                    final kbps = int.tryParse(data.targetBitrate ?? '');
                    final bitrate = switch (kbps) {
                      null => '—',
                      < 1000 => '$kbps kb/s',
                      _ => '${kbps / 1000} Mb/s',
                    };
                    final delay = data.delay == null
                        ? '—'
                        : '${(data.fps ?? "").replaceAll(" ", "").replaceAll("0", "").isEmpty ? 0 : data.delay} ms';
                    final direct = model.directConnection;
                    return Visibility(
                      visible: model.show,
                      maintainState: true,
                      child: MobileSessionQualityMonitor(
                        connection: direct == null
                            ? translate('Quality')
                            : '${translate(direct ? "Direct Connection" : "Relay Connection")} · ${model.activeTransport ?? "—"}',
                        direct: direct,
                        metrics: [
                          (translate('Speed'), data.speed ?? '—'),
                          ('FPS', data.fps ?? '—'),
                          (translate('Delay'), delay),
                          (translate('Bitrate'), bitrate),
                          (translate('Codec'), data.codecFormat ?? '—'),
                          (translate('Chroma'), data.chroma ?? '—'),
                        ],
                        diagnostics: model.udpReports.isEmpty
                            ? null
                            : PeerUdpButton(model, foreground: Colors.white),
                      ),
                    );
                  },
                ),
              )
            else
              Positioned(
                top: 10,
                left: _usesAwesunOverlay ? 10 : null,
                right: _usesAwesunOverlay ? null : 10,
                child: QualityMonitor(gFFI.qualityMonitorModel),
              ),
            if (!isMobile)
              Obx(() {
                final chatKeyboardRequested =
                    gFFI.chatModel.softKeyboardRequested.value;
                return KeyHelpTools(
                    keyboardIsVisible: keyboardVisibilityController.isVisible &&
                        (_showEdit || chatKeyboardRequested),
                    showGestureHelp: _showGestureHelp);
              }),
            if (!isMobile)
              SizedBox(
                width: 0,
                height: 0,
                child: !_showEdit
                    ? Container()
                    : TextFormField(
                        textInputAction: TextInputAction.newline,
                        autocorrect: false,
                        // Flutter 3.16.9 Android.
                        // `enableSuggestions` causes secure keyboard to be shown.
                        // https://github.com/flutter/flutter/issues/139143
                        // https://github.com/flutter/flutter/issues/146540
                        // enableSuggestions: false,
                        autofocus: true,
                        focusNode: _mobileFocusNode,
                        maxLines: null,
                        controller: _textController,
                        // trick way to make backspace work always
                        keyboardType: TextInputType.multiline,
                        // `onChanged` may be called depending on the input method if this widget is wrapped in
                        // `Focus(onKeyEvent: ..., child: ...)`
                        // For `Backspace` button in the soft keyboard:
                        // en/fr input method:
                        //      1. The button will not trigger `onKeyEvent` if the text field is not empty.
                        //      2. The button will trigger `onKeyEvent` if the text field is empty.
                        // ko/zh/ja input method: the button will trigger `onKeyEvent`
                        //                     and the event will not popup if `KeyEventResult.handled` is returned.
                        onChanged: handleSoftKeyboardInput,
                      ).workaroundFreezeLinuxMint(),
              ),
          ];
          if (showCursorPaint && !_nativePointerVisible) {
            paints.add(CursorPaint(widget.id));
          }
          if (!_usesAwesunOverlay && gFFI.ffiModel.touchMode && !isMobile) {
            paints.add(FloatingMouse(
              ffi: gFFI,
            ));
          } else if (!_usesAwesunOverlay &&
              !gFFI.ffiModel.touchMode &&
              !_showSessionKeyboard) {
            paints.add(FloatingMouseWidgets(
              ffi: gFFI,
            ));
          }
          return paints;
        }()));
  }

  Widget getBodyForDesktopWithListener() {
    final ffiModel = Provider.of<FfiModel>(context);
    var paints = <Widget>[ImagePaint(ffiModel: ffiModel)];
    if (showCursorPaint) {
      final cursor = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: 'show-remote-cursor');
      if (ffiModel.keyboard || cursor) {
        paints.add(CursorPaint(widget.id));
      }
    }
    return Container(
        color: MyTheme.canvasColor, child: Stack(children: paints));
  }

  List<TTextMenu> _getMobileActionMenus() {
    if (gFFI.ffiModel.pi.platform != kPeerPlatformAndroid ||
        !gFFI.ffiModel.keyboard) {
      return [];
    }
    final enabled = versionCmp(gFFI.ffiModel.pi.version, '1.2.7') >= 0;
    if (!enabled) return [];
    return [
      TTextMenu(
        child: Text(translate('Back')),
        onPressed: () => gFFI.inputModel.onMobileBack(),
      ),
      TTextMenu(
        child: Text(translate('Home')),
        onPressed: () => gFFI.inputModel.onMobileHome(),
      ),
      TTextMenu(
        child: Text(translate('Apps')),
        onPressed: () => gFFI.inputModel.onMobileApps(),
      ),
      TTextMenu(
        child: Text(translate('Volume up')),
        onPressed: () => gFFI.inputModel.onMobileVolumeUp(),
      ),
      TTextMenu(
        child: Text(translate('Volume down')),
        onPressed: () => gFFI.inputModel.onMobileVolumeDown(),
      ),
      TTextMenu(
        child: Text(translate('Power')),
        onPressed: () => gFFI.inputModel.onMobilePower(),
      ),
    ];
  }

  Future<void> _copyP2pDiagnostics() async {
    if (!recordIosP2pDiagnostics) return;
    try {
      final documents = await getApplicationDocumentsDirectory();
      final report = await readIosP2pDiagnostics(documents, _sessionOpened);
      if (!mounted || !recordIosP2pDiagnostics) return;
      final peerRows = gFFI.qualityMonitorModel.udpReports.join('\n\n');
      final localRows = gFFI.qualityMonitorModel.localUdpReports.values.join('\n\n');
      if (report == null && peerRows.isEmpty) {
        showToast(translate('Waiting'));
        return;
      }
      final quality = gFFI.qualityMonitorModel;
      final data = quality.data;
      final media = formatIosMediaSample(
        opened: _sessionOpened, now: DateTime.now(), videoAt: quality.lastVideoSample,
        delayAt: quality.lastDelaySample, codec: data.codecFormat, chroma: data.chroma,
        fps: data.fps, delay: data.delay, target: data.targetBitrate,
        direct: gFFI.ffiModel.direct, transport: gFFI.ffiModel.cachedPeerData.streamType,
      );
      final ready = gFFI.imageModel.imageReady.format(_sessionOpened, DateTime.now());
      await Clipboard.setData(ClipboardData(text: [if (report != null) report, if (localRows.isNotEmpty) 'controller UDP\n$localRows', if (peerRows.isNotEmpty) 'controlled UDP\n$peerRows', '$media$ready'].join('\n')));
      if (mounted) showToast(translate('Copied'));
    } catch (_) {
      if (mounted) showToast(translate('Failed'));
    }
  }

  void showActions(String id) async {
    final size = MediaQuery.of(context).size;
    final x = 120.0;
    final y = size.height;
    final mobileActionMenus = [
      if (isIOS && recordIosP2pDiagnostics)
        TTextMenu(
          child: Text(translate('Copy P2P diagnostics')),
          trailingIcon: const Icon(Icons.content_copy),
          onPressed: _copyP2pDiagnostics,
        ),
      ..._getMobileActionMenus(),
    ];
    final menus = toolbarControls(context, id, gFFI);

    final List<PopupMenuEntry<int>> more = [
      ...mobileActionMenus
          .asMap()
          .entries
          .map((e) =>
              PopupMenuItem<int>(child: e.value.getChild(), value: e.key))
          .toList(),
      if (mobileActionMenus.isNotEmpty) PopupMenuDivider(),
      ...menus
          .asMap()
          .entries
          .map((e) => PopupMenuItem<int>(
              child: e.value.getChild(),
              value: e.key + mobileActionMenus.length))
          .toList(),
    ];
    () async {
      var index = await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(x, y, x, y),
        items: more,
        elevation: 8,
      );
      if (index != null) {
        if (index < mobileActionMenus.length) {
          mobileActionMenus[index].onPressed?.call();
        } else if (index < mobileActionMenus.length + more.length) {
          menus[index - mobileActionMenus.length].onPressed?.call();
        }
      }
    }();
  }

  void _registerMobileChatShortcut() {
    if (!isMobile) return;
    gFFI.shortcutModel.register(kShortcutActionToggleChat,
        () => onPressedTextChat(widget.id, requestSoftKeyboard: false));
  }

  onPressedTextChat(String id, {bool requestSoftKeyboard = true}) {
    if (gFFI.chatModel.chatWindowOverlayEntry == null) {
      setState(() {
        _showEdit = false;
        if (isMobile) {
          _showSessionKeyboard = false;
          _timer?.cancel();
          _iosKeyboardWorkaroundTimer?.cancel();
        }
      });
    }
    gFFI.chatModel.changeCurrentKey(MessageKey(id, ChatModel.clientModeID));
    gFFI.chatModel.toggleChatOverlay(requestSoftKeyboard: requestSoftKeyboard);
  }

  showChatOptions(String id) async {
    onPressVoiceCall() => bind.sessionRequestVoiceCall(sessionId: sessionId);
    onPressEndVoiceCall() => bind.sessionCloseVoiceCall(sessionId: sessionId);

    makeTextMenu(String label, Widget icon, VoidCallback onPressed,
            {TextStyle? labelStyle}) =>
        TTextMenu(
          child: Text(translate(label), style: labelStyle),
          trailingIcon: Transform.scale(
            scale: (isDesktop || isWebDesktop) ? 0.8 : 1,
            child: IgnorePointer(
              child: IconButton(
                onPressed: null,
                icon: icon,
              ),
            ),
          ),
          onPressed: onPressed,
        );

    final isInVoice = [
      VoiceCallStatus.waitingForResponse,
      VoiceCallStatus.connected
    ].contains(gFFI.chatModel.voiceCallStatus.value);
    final menus = [
      makeTextMenu('Text chat', Icon(Icons.message, color: MyTheme.accent),
          () => onPressedTextChat(widget.id)),
      isInVoice
          ? makeTextMenu(
              'End voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter:
                    ColorFilter.mode(Colors.redAccent, BlendMode.srcIn),
              ),
              onPressEndVoiceCall,
              labelStyle: TextStyle(color: Colors.redAccent))
          : makeTextMenu(
              'Voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter: ColorFilter.mode(MyTheme.accent, BlendMode.srcIn),
              ),
              onPressVoiceCall),
    ];

    final menuItems = menus
        .asMap()
        .entries
        .map((e) => PopupMenuItem<int>(child: e.value.getChild(), value: e.key))
        .toList();
    Future.delayed(Duration.zero, () async {
      final size = MediaQuery.of(context).size;
      final x = 120.0;
      final y = size.height;
      var index = await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(x, y, x, y),
        items: menuItems,
        elevation: 8,
      );
      if (index != null && index < menus.length) {
        menus[index].onPressed?.call();
      }
    });
  }

  /// aka changeTouchMode
  BottomAppBar getGestureHelp() {
    return BottomAppBar(
        child: SingleChildScrollView(
            controller: ScrollController(),
            padding: EdgeInsets.symmetric(vertical: 10),
            child: GestureHelp(
              touchMode: gFFI.ffiModel.touchMode,
              onTouchModeChange: (t) {
                gFFI.ffiModel.toggleTouchMode();
                final v = gFFI.ffiModel.touchMode ? 'Y' : 'N';
                bind.mainSetLocalOption(key: kOptionTouchMode, value: v);
              },
              virtualMouseMode: gFFI.ffiModel.virtualMouseMode,
              inputModel: gFFI.inputModel,
            )));
  }

  // * Currently mobile does not enable map mode
  // void changePhysicalKeyboardInputMode() async {
  //   var current = await bind.sessionGetKeyboardMode(id: widget.id) ?? "legacy";
  //   gFFI.dialogManager.show((setState, close) {
  //     void setMode(String? v) async {
  //       await bind.sessionSetKeyboardMode(id: widget.id, value: v ?? "");
  //       setState(() => current = v ?? '');
  //       Future.delayed(Duration(milliseconds: 300), close);
  //     }
  //
  //     return CustomAlertDialog(
  //         title: Text(translate('Physical Keyboard Input Mode')),
  //         content: Column(mainAxisSize: MainAxisSize.min, children: [
  //           getRadio('Legacy mode', 'legacy', current, setMode),
  //           getRadio('Map mode', 'map', current, setMode),
  //         ]));
  //   }, clickMaskDismiss: true);
  // }
}

class KeyHelpTools extends StatefulWidget {
  final bool keyboardIsVisible;
  final bool showGestureHelp;

  /// need to show by external request, etc [keyboardIsVisible] or [changeTouchMode]
  bool get requestShow => keyboardIsVisible || showGestureHelp;

  KeyHelpTools(
      {required this.keyboardIsVisible, required this.showGestureHelp});

  @override
  State<KeyHelpTools> createState() => _KeyHelpToolsState();
}

class _KeyHelpToolsState extends State<KeyHelpTools> {
  var _more = true;
  var _fn = false;
  var _pin = false;
  final _keyboardVisibilityController = KeyboardVisibilityController();
  final _key = GlobalKey();

  InputModel get inputModel => gFFI.inputModel;

  Widget wrap(String text, void Function() onPressed,
      {bool? active, IconData? icon}) {
    return TextButton(
        style: TextButton.styleFrom(
          minimumSize: Size(0, 0),
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 9.75),
          //adds padding inside the button
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          //limits the touch area to the button area
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5.0),
          ),
          backgroundColor: active == true ? MyTheme.accent80 : null,
        ),
        child: icon != null
            ? Icon(icon, size: 14, color: Colors.white)
            : Text(translate(text),
                style: TextStyle(color: Colors.white, fontSize: 11)),
        onPressed: onPressed);
  }

  _updateRect() {
    RenderObject? renderObject = _key.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      Offset pos = renderObject.localToGlobal(Offset.zero);
      gFFI.cursorModel.keyHelpToolsVisibilityChanged(
          Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height),
          widget.keyboardIsVisible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = HardwareKeyboard.instance;
    // Keep touch selections visible without physical modifiers opening the bar.
    final hasTouchModifier = (inputModel.ctrl && !keyboard.isControlPressed) ||
        (inputModel.alt && !keyboard.isAltPressed) ||
        (inputModel.shift && !keyboard.isShiftPressed) ||
        (inputModel.command && !keyboard.isMetaPressed);
    if (!_pin && !hasTouchModifier && !widget.requestShow) {
      gFFI.cursorModel
          .keyHelpToolsVisibilityChanged(null, widget.keyboardIsVisible);
      return Offstage();
    }
    final size = MediaQuery.of(context).size;

    final pi = gFFI.ffiModel.pi;
    final isMac = pi.platform == kPeerPlatformMacOS;
    final isWin = pi.platform == kPeerPlatformWindows;
    final isLinux = pi.platform == kPeerPlatformLinux;
    final modifiers = <Widget>[
      wrap('Ctrl ', () {
        setState(() => inputModel.ctrl = !inputModel.ctrl);
      }, active: inputModel.ctrl),
      wrap(' Alt ', () {
        setState(() => inputModel.alt = !inputModel.alt);
      }, active: inputModel.alt),
      wrap('Shift', () {
        setState(() => inputModel.shift = !inputModel.shift);
      }, active: inputModel.shift),
      wrap(isMac ? ' Cmd ' : ' Win ', () {
        setState(() => inputModel.command = !inputModel.command);
      }, active: inputModel.command),
    ];
    final keys = <Widget>[
      wrap(
          ' Fn ',
          () => setState(
                () {
                  _fn = !_fn;
                  if (_fn) {
                    _more = false;
                  }
                },
              ),
          active: _fn),
      wrap(
          '',
          () => setState(
                () => _pin = !_pin,
              ),
          active: _pin,
          icon: Icons.push_pin),
      wrap(
          ' ... ',
          () => setState(
                () {
                  _more = !_more;
                  if (_more) {
                    _fn = false;
                  }
                },
              ),
          active: _more),
    ];
    final fn = <Widget>[
      SizedBox(width: 9999),
    ];
    for (var i = 1; i <= 12; ++i) {
      final name = 'F$i';
      fn.add(wrap(name, () {
        inputModel.inputKey('VK_$name');
      }));
    }
    final more = <Widget>[
      SizedBox(width: 9999),
      wrap('Esc', () {
        inputModel.inputKey('VK_ESCAPE');
      }),
      wrap('Tab', () {
        inputModel.inputKey('VK_TAB');
      }),
      wrap('Home', () {
        inputModel.inputKey('VK_HOME');
      }),
      wrap('End', () {
        inputModel.inputKey('VK_END');
      }),
      wrap('Ins', () {
        inputModel.inputKey('VK_INSERT');
      }),
      wrap('Del', () {
        inputModel.inputKey('VK_DELETE');
      }),
      wrap('PgUp', () {
        inputModel.inputKey('VK_PRIOR');
      }),
      wrap('PgDn', () {
        inputModel.inputKey('VK_NEXT');
      }),
      // to-do: support PrtScr on Mac
      if (isWin || isLinux)
        wrap('PrtScr', () {
          inputModel.inputKey('VK_SNAPSHOT');
        }),
      if (isWin || isLinux)
        wrap('ScrollLock', () {
          inputModel.inputKey('VK_SCROLL');
        }),
      if (isWin || isLinux)
        wrap('Pause', () {
          inputModel.inputKey('VK_PAUSE');
        }),
      if (isWin || isLinux)
        // Maybe it's better to call it "Menu"
        // https://en.wikipedia.org/wiki/Menu_key
        wrap('Menu', () {
          inputModel.inputKey('Apps');
        }),
      wrap('Enter', () {
        inputModel.inputKey('VK_ENTER');
      }),
      SizedBox(width: 9999),
      wrap('', () {
        inputModel.inputKey('VK_LEFT');
      }, icon: Icons.keyboard_arrow_left),
      wrap('', () {
        inputModel.inputKey('VK_UP');
      }, icon: Icons.keyboard_arrow_up),
      wrap('', () {
        inputModel.inputKey('VK_DOWN');
      }, icon: Icons.keyboard_arrow_down),
      wrap('', () {
        inputModel.inputKey('VK_RIGHT');
      }, icon: Icons.keyboard_arrow_right),
      wrap(isMac ? 'Cmd+C' : 'Ctrl+C', () {
        sendPrompt(isMac, 'VK_C');
      }),
      wrap(isMac ? 'Cmd+V' : 'Ctrl+V', () {
        sendPrompt(isMac, 'VK_V');
      }),
      wrap(isMac ? 'Cmd+S' : 'Ctrl+S', () {
        sendPrompt(isMac, 'VK_S');
      }),
    ];
    final space = size.width > 320 ? 4.0 : 2.0;
    // 500 ms is long enough for this widget to be built!
    Future.delayed(Duration(milliseconds: 500), () {
      _updateRect();
    });
    return Container(
        key: _key,
        color: Color(0xAA000000),
        padding: EdgeInsets.only(
            top: _keyboardVisibilityController.isVisible ? 24 : 4, bottom: 8),
        child: Wrap(
          spacing: space,
          runSpacing: space,
          children: <Widget>[SizedBox(width: 9999)] +
              modifiers +
              keys +
              (_fn ? fn : []) +
              (_more ? more : []),
        ));
  }
}

class ImagePaint extends StatelessWidget {
  final FfiModel ffiModel;
  ImagePaint({Key? key, required this.ffiModel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<ImageModel>(context);
    final c = Provider.of<CanvasModel>(context);
    var s = c.scale;
    if (ffiModel.isPeerLinux) {
      final displays = ffiModel.pi.getCurDisplays();
      if (displays.isNotEmpty) {
        s = s / displays[0].scale;
      }
    }
    final adjust = c.getAdjustY();
    return CustomPaint(
      painter: ImagePainter(
          image: m.image, x: c.x / s, y: (c.y + adjust) / s, scale: s),
    );
  }
}

class CursorPaint extends StatelessWidget {
  late final String id;
  CursorPaint(this.id);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<CursorModel>(context);
    final c = Provider.of<CanvasModel>(context);
    final ffiModel = Provider.of<FfiModel>(context);
    final s = c.scale;
    double hotx = m.hotx;
    double hoty = m.hoty;
    var image = m.image;
    if (image == null) {
      if (preDefaultCursor.image != null) {
        image = preDefaultCursor.image;
        hotx = preDefaultCursor.image!.width / 2;
        hoty = preDefaultCursor.image!.height / 2;
      }
    }
    if (preForbiddenCursor.image != null &&
        !ffiModel.viewOnly &&
        !ffiModel.keyboard &&
        !ShowRemoteCursorState.find(id).value) {
      image = preForbiddenCursor.image;
      hotx = preForbiddenCursor.image!.width / 2;
      hoty = preForbiddenCursor.image!.height / 2;
    }
    if (image == null) {
      return Offstage();
    }

    final minSize = 12.0;
    double mins =
        minSize / (image.width > image.height ? image.width : image.height);
    double factor = 1.0;
    if (s < mins) {
      factor = s / mins;
    }
    final s2 = s < mins ? mins : s;
    final adjust = c.getAdjustY();
    return CustomPaint(
      painter: ImagePainter(
          image: image,
          x: (m.x - hotx) * factor + c.x / s2,
          y: (m.y - hoty) * factor + (c.y + adjust) / s2,
          scale: s2),
    );
  }
}

void showOptions(
    BuildContext context, String id, OverlayDialogManager dialogManager) async {
  var displays = <Widget>[];
  final pi = gFFI.ffiModel.pi;
  final image = gFFI.ffiModel.getConnectionImageText(peerId: id);
  if (image != null) {
    displays.add(Padding(padding: const EdgeInsets.only(top: 8), child: image));
  }
  final privacyModeState = PrivacyModeState.find(id);
  if (pi.displays.length > 1 &&
      pi.currentDisplay != kAllDisplayValue &&
      (privacyModeState.isEmpty ||
          allowDisplaySwitchInPrivacyMode(pi, privacyModeState.value))) {
    final cur = pi.currentDisplay;
    final children = <Widget>[];
    final isDarkTheme = MyTheme.currentThemeMode() == ThemeMode.dark;
    final numColorSelected = Colors.white;
    final numColorUnselected = isDarkTheme ? Colors.grey : Colors.black87;
    // We can't use `Theme.of(context).primaryColor` here, the color is:
    // - light theme: 0xff2196f3 (Colors.blue)
    // - dark theme: 0xff212121 (the canvas color?)
    final numBgSelected =
        Theme.of(context).colorScheme.primary.withOpacity(0.6);
    for (var i = 0; i < pi.displays.length; ++i) {
      children.add(InkWell(
          onTap: () {
            if (i == cur) return;
            openMonitorInTheSameTab(i, gFFI, pi);
            gFFI.dialogManager.dismissAll();
          },
          child: Ink(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).hintColor),
                  borderRadius: BorderRadius.circular(2),
                  color: i == cur ? numBgSelected : null),
              child: Center(
                  child: Text((i + 1).toString(),
                      style: TextStyle(
                          color:
                              i == cur ? numColorSelected : numColorUnselected,
                          fontWeight: FontWeight.bold))))));
    }
    displays.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: children,
        )));
  }
  if (displays.isNotEmpty) {
    displays.add(const Divider(color: MyTheme.border));
  }

  List<TRadioMenu<String>> viewStyleRadios =
      await toolbarViewStyle(context, id, gFFI);
  List<TRadioMenu<String>> imageQualityRadios =
      await toolbarImageQuality(context, id, gFFI);
  List<TRadioMenu<String>> codecRadios = await toolbarCodec(context, id, gFFI);
  List<TToggleMenu> cursorToggles = await toolbarCursor(context, id, gFFI);
  List<TToggleMenu> displayToggles =
      await toolbarDisplayToggle(context, id, gFFI);
  if (isMobile) {
    displayToggles.insert(
        0,
        TToggleMenu(
            child: Text(translate('Lock canvas')),
            value: gFFI.canvasModel.locked,
            onChanged: (value) => gFFI.canvasModel.setLocked(value == true)));
  }

  List<TToggleMenu> privacyModeList = [];
  if ((gFFI.ffiModel.pi.features.privacyMode && gFFI.ffiModel.keyboard) ||
      privacyModeState.isNotEmpty) {
    privacyModeList = toolbarPrivacyMode(privacyModeState, context, id, gFFI);
    if (privacyModeList.length == 1) {
      displayToggles.add(privacyModeList[0]);
    }
  }

  dialogManager.show((setState, close, context) {
    var viewStyle =
        (viewStyleRadios.isNotEmpty ? viewStyleRadios[0].groupValue : '').obs;
    var imageQuality =
        (imageQualityRadios.isNotEmpty ? imageQualityRadios[0].groupValue : '')
            .obs;
    var codec = (codecRadios.isNotEmpty ? codecRadios[0].groupValue : '').obs;
    final radios = [
      for (var e in viewStyleRadios)
        Obx(() => getRadio<String>(
            e.child,
            e.value,
            viewStyle.value,
            e.onChanged != null
                ? (v) {
                    e.onChanged?.call(v);
                    if (v != null) viewStyle.value = v;
                  }
                : null)),
      // Show custom scale controls when custom view style is selected
      Obx(() => viewStyle.value == kRemoteViewStyleCustom
          ? MobileCustomScaleControls(ffi: gFFI)
          : const SizedBox.shrink()),
      const Divider(color: MyTheme.border),
      for (var e in imageQualityRadios)
        Obx(() => getRadio<String>(
            e.child,
            e.value,
            imageQuality.value,
            e.onChanged != null
                ? (v) {
                    e.onChanged?.call(v);
                    if (v != null) imageQuality.value = v;
                  }
                : null)),
      const Divider(color: MyTheme.border),
      for (var e in codecRadios)
        Obx(() => getRadio<String>(
            e.child,
            e.value,
            codec.value,
            e.onChanged != null
                ? (v) {
                    e.onChanged?.call(v);
                    if (v != null) codec.value = v;
                  }
                : null)),
      if (codecRadios.isNotEmpty) const Divider(color: MyTheme.border),
    ];
    final rxCursorToggleValues = cursorToggles.map((e) => e.value.obs).toList();
    final cursorTogglesList = cursorToggles
        .asMap()
        .entries
        .map((e) => Obx(() => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            value: rxCursorToggleValues[e.key].value,
            onChanged: e.value.onChanged != null
                ? (v) {
                    e.value.onChanged?.call(v);
                    if (v != null) rxCursorToggleValues[e.key].value = v;
                  }
                : null,
            title: e.value.child)))
        .toList();

    final rxToggleValues = displayToggles.map((e) => e.value.obs).toList();
    final displayTogglesList = displayToggles
        .asMap()
        .entries
        .map((e) => Obx(() => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            value: rxToggleValues[e.key].value,
            onChanged: e.value.onChanged != null
                ? (v) {
                    e.value.onChanged?.call(v);
                    if (v != null) rxToggleValues[e.key].value = v;
                  }
                : null,
            title: e.value.child)))
        .toList();
    final toggles = [
      ...cursorTogglesList,
      if (cursorToggles.isNotEmpty) const Divider(color: MyTheme.border),
      ...displayTogglesList,
    ];

    Widget privacyModeWidget = Offstage();
    if (privacyModeList.length > 1) {
      privacyModeWidget = ListTile(
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: Text(translate('Privacy mode')),
        onTap: () => setPrivacyModeDialog(
            dialogManager, privacyModeList, privacyModeState),
      );
    }

    var popupDialogMenus = List<Widget>.empty(growable: true);
    final resolution = getResolutionMenu(gFFI, id);
    if (resolution != null) {
      popupDialogMenus.add(ListTile(
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: resolution.child,
        onTap: () {
          close();
          resolution.onPressed?.call();
        },
      ));
    }
    final virtualDisplayMenu = getVirtualDisplayMenu(gFFI, id);
    if (virtualDisplayMenu != null) {
      popupDialogMenus.add(ListTile(
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: virtualDisplayMenu.child,
        onTap: () {
          close();
          virtualDisplayMenu.onPressed?.call();
        },
      ));
    }
    if (popupDialogMenus.isNotEmpty) {
      popupDialogMenus.add(const Divider(color: MyTheme.border));
    }

    return CustomAlertDialog(
      content: Column(
          mainAxisSize: MainAxisSize.min,
          children: displays +
              radios +
              popupDialogMenus +
              toggles +
              [privacyModeWidget]),
    );
  }, clickMaskDismiss: true, backDismiss: true).then((value) {
    _disableAndroidSoftKeyboard();
  });
}

TTextMenu? getVirtualDisplayMenu(FFI ffi, String id) {
  if (!showVirtualDisplayMenu(ffi)) {
    return null;
  }
  return TTextMenu(
    child: Text(translate("Virtual display")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = getVirtualDisplayMenuChildren(ffi, id, close);
        return CustomAlertDialog(
          title: Text(translate('Virtual display')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

TTextMenu? getResolutionMenu(FFI ffi, String id) {
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  final resolutions = pi.resolutions;
  final display = pi.tryGetDisplayIfNotAllDisplay(display: pi.currentDisplay);

  final visible =
      ffiModel.keyboard && (resolutions.length > 1) && display != null;
  if (!visible) return null;

  return TTextMenu(
    child: Text(translate("Resolution")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = resolutions
            .map((e) => getRadio<String>(
                  Text('${e.width}x${e.height}'),
                  '${e.width}x${e.height}',
                  '${display.width}x${display.height}',
                  (value) {
                    close();
                    bind.sessionChangeResolution(
                      sessionId: ffi.sessionId,
                      display: pi.currentDisplay,
                      width: e.width,
                      height: e.height,
                    );
                  },
                ))
            .toList();
        return CustomAlertDialog(
          title: Text(translate('Resolution')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

void sendPrompt(bool isMac, String key) {
  final old = isMac ? gFFI.inputModel.command : gFFI.inputModel.ctrl;
  if (isMac) {
    gFFI.inputModel.command = true;
  } else {
    gFFI.inputModel.ctrl = true;
  }
  gFFI.inputModel.inputKey(key);
  if (isMac) {
    gFFI.inputModel.command = old;
  } else {
    gFFI.inputModel.ctrl = old;
  }
}

class FABLocation extends FloatingActionButtonLocation {
  FloatingActionButtonLocation location;
  double offsetX;
  double offsetY;
  FABLocation(this.location, this.offsetX, this.offsetY);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final offset = location.getOffset(scaffoldGeometry);
    return Offset(offset.dx + offsetX, offset.dy + offsetY);
  }
}
