import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
import '../consts.dart';
import '../models/model.dart';

class PhoneMicrophone {
  static const _ios = MethodChannel('rustdesk/phone-microphone');
  static FFI? _owner;
  static final _standalone = Rxn<FFI>();
  static FFI? get standalone => _standalone.value;
  static String peerId = '';
  static DateTime? openedAt;
  static bool _preparing = false;
  static bool owns(FFI? session) =>
      session != null && identical(session, _owner);

  static Future<FFI?> startStandalone(String id, bool forceRelay) async {
    final existing = standalone;
    if (existing != null && !existing.closed) {
      if (peerId != id) showToast(translate('Phone microphone is in use'));
      return peerId == id ? existing : null;
    }
    if (existing != null) connectionEnded(existing);
    if (_owner != null || _preparing) {
      showToast(translate('Phone microphone is in use'));
      return null;
    }
    final session = FFI(const Uuid().v4obj());
    try {
      openedAt = DateTime.now();
      peerId = id;
      _standalone.value = session;
      session.start(id, phoneMicrophoneOnly: true, forceRelay: forceRelay);
      return session;
    } catch (error) {
      debugPrint('Could not start audio session: $error');
      connectionEnded(session);
      showToast(error.toString());
      return null;
    }
  }

  static void connectionEnded(FFI session) {
    if (!identical(standalone, session)) return;
    openedAt = null;
    peerId = '';
    _standalone.value = null;
    unawaited(stop(session));
  }

  static Future<void> disconnect(FFI session) async {
    if (!identical(standalone, session)) return;
    session.dialogManager.dismissAll();
    try {
      await session.close();
    } finally {
      connectionEnded(session);
    }
  }

  static Future<bool> prepare(FFI session) async {
    if (_owner != null ||
        _preparing ||
        (standalone != null && !identical(standalone, session))) {
      showToast(translate('Phone microphone is in use'));
      return false;
    }
    _preparing = true;
    try {
      if (isAndroid &&
          !await AndroidPermissionManager.check(kRecordAudio) &&
          !await AndroidPermissionManager.request(kRecordAudio)) return false;
      final granted = isIOS
          ? await _ios.invokeMethod<bool>('prepare') == true
          : isAndroid &&
              await gFFI.invokeMethod('prepare_phone_microphone') == true;
      if (granted) _owner = session;
      return granted;
    } on PlatformException catch (error) {
      showToast(error.message ?? translate('Failed'));
      return false;
    } finally {
      _preparing = false;
    }
  }

  static Future<void> stop(FFI session) async {
    if (!owns(session)) return;
    _owner = null;
    _preparing = true;
    try {
      if (isIOS) {
        await _ios.invokeMethod<void>('stop', !session.closed);
      } else if (isAndroid) {
        await gFFI.invokeMethod('stop_phone_microphone');
      }
    } on PlatformException catch (error) {
      showToast(error.message ?? translate('Failed'));
    } finally {
      _preparing = false;
    }
  }
}
