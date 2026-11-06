import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';

enum PushAuthorization { granted, denied, undetermined, unsupported }

abstract class PushAccess {
  Future<PushAuthorization> authorization({required bool requestPermission});
  Future<String> register();
  Future<void> unregister();
}

/// Device-local choices, separate from OS permission and server registration.
class PushPreferences extends ChangeNotifier {
  PushPreferences({
    required this.access,
    required this.writeDevice,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final PushAccess access;
  final DateTime Function() _clock;

  /// An unchanged registration is re-sent to the server at most this often.
  static const registrationRefresh = Duration(days: 7);
  // Device-wide: the server keys a device by its token, so only one account
  // can hold this registration at a time.
  static const _registrationKey = 'meokkiri.pushRegistration.v1';
  final Future<void> Function(String uid, String token, bool enabled)
  writeDevice;
  String? accountId;
  bool enabled = false, supported = true, blocked = false;
  String? message;
  bool _desired = false, _disposed = false;
  int _epoch = 0, _pending = 0;
  Future<void> _tail = Future.value();
  bool get busy => _pending > 0;
  String _choiceKey(String uid) => 'meokkiri.pushEnabled.v1.$uid';
  String _tokenKey(String uid) => 'meokkiri.pushDevice.v1.$uid';

  bool _recentlyRegistered(SharedPreferences prefs, String uid, String token) {
    try {
      final raw = prefs.getString(_registrationKey);
      if (raw == null) return false;
      final row = jsonDecode(raw) as Map<String, dynamic>;
      final age = _clock().difference(
        DateTime.fromMillisecondsSinceEpoch(row['at'] as int),
      );
      return row['uid'] == uid &&
          row['token'] == token &&
          !age.isNegative &&
          age < registrationRefresh;
    } catch (_) {
      return false;
    }
  }

  /// Writes the server registration and remembers which account holds it.
  Future<void> _write(String uid, String token, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await writeDevice(uid, token, false);
      try {
        final raw = prefs.getString(_registrationKey);
        if (raw != null && (jsonDecode(raw) as Map)['token'] == token) {
          await prefs.remove(_registrationKey);
        }
      } catch (_) {
        await prefs.remove(_registrationKey);
      }
      return;
    }
    await writeDevice(uid, token, true);
    await prefs.setString(
      _registrationKey,
      jsonEncode({
        'uid': uid,
        'token': token,
        'at': _clock().millisecondsSinceEpoch,
      }),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _queue(Future<void> Function() action) {
    _pending++;
    final task = _tail.then((_) => action());
    _tail = task.then<void>((_) {}, onError: (Object _) {});
    _notify();
    return task.whenComplete(() {
      _pending--;
      _notify();
    });
  }

  bool _current(String uid, int epoch) => accountId == uid && epoch == _epoch;

  Future<void> bind(String? uid) {
    final previous = accountId;
    accountId = uid;
    final epoch = ++_epoch;
    _desired = false;
    enabled = false;
    blocked = false;
    message = null;
    return _queue(() async {
      if (previous != null && previous != uid) {
        try {
          await _stop(previous);
        } catch (_) {
          // A persisted registration is retried when that account signs in again.
        }
      }
      if (uid != null && _current(uid, epoch)) {
        await _restore(uid, epoch);
      }
    });
  }

  Future<void> refresh() {
    final uid = accountId, epoch = _epoch;
    if (uid == null || busy) return Future.value();
    return _queue(() => _restore(uid, epoch));
  }

  Future<void> detach() {
    final uid = accountId;
    if (uid == null) return Future.value();
    _desired = false;
    ++_epoch;
    return _queue(() async {
      await _stop(uid);
      enabled = false;
    });
  }

  Future<void> _restore(String uid, int epoch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final permission = await access.authorization(requestPermission: false);
      if (!_current(uid, epoch)) return;
      supported = permission != PushAuthorization.unsupported;
      // Retain an already granted pre-switch permission on upgrade. An explicit
      // off choice always wins, including after OS permission changes or login.
      _desired =
          prefs.getBool(_choiceKey(uid)) ??
          permission == PushAuthorization.granted;
      if (!_desired || permission != PushAuthorization.granted) {
        blocked = _desired && supported;
        enabled = false;
        if (prefs.getString(_tokenKey(uid)) != null) await _stop(uid);
        return;
      }
      blocked = false;
      await _register(uid, epoch);
    } catch (_) {
      if (_current(uid, epoch)) {
        enabled = false;
        message = '알림 상태를 확인하지 못했어요. 연결을 확인하고 다시 시도해 주세요.';
      }
    }
  }

  Future<void> setEnabled(bool value) {
    final uid = accountId;
    if (uid == null) {
      return Future.error(const LunchException('로그인 후 이용해 주세요.'));
    }
    final epoch = ++_epoch;
    _desired = value;
    message = null;
    return _queue(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_choiceKey(uid), value);
      if (!_current(uid, epoch)) return;
      if (!value) {
        try {
          await _stop(uid);
          if (_current(uid, epoch)) {
            enabled = false;
            blocked = false;
          }
        } catch (_) {
          message = '알림 끄기를 완료하지 못했어요. 연결을 확인하고 다시 시도해 주세요.';
          rethrow;
        }
        return;
      }
      try {
        final permission = await access.authorization(requestPermission: true);
        if (!_current(uid, epoch)) return;
        supported = permission != PushAuthorization.unsupported;
        if (permission != PushAuthorization.granted) {
          enabled = false;
          blocked = supported;
          _desired = false;
          await prefs.setBool(_choiceKey(uid), false);
          message = supported
              ? '기기나 브라우저 설정에서 알림을 허용한 뒤 다시 켜 주세요.'
              : '이 기기·브라우저에서는 Push 알림을 지원하지 않아요.';
          return;
        }
        blocked = false;
        await _register(uid, epoch);
      } catch (_) {
        if (_current(uid, epoch)) {
          enabled = false;
          message = '알림을 켜지 못했어요. 연결을 확인하고 다시 시도해 주세요.';
        }
        rethrow;
      }
    });
  }

  Future<void> _register(String uid, int epoch) async {
    final token = await access.register();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey(uid), token);
    if (!_current(uid, epoch) || !_desired) return;
    // Resuming the app re-checks permission and the token, but an unchanged
    // registration confirmed recently is not written to the server again.
    if (!_recentlyRegistered(prefs, uid, token)) {
      await _write(uid, token, true);
    }
    if (_current(uid, epoch) && _desired) {
      enabled = true;
      message = null;
    }
  }

  Future<void> registered(String token) {
    final uid = accountId, epoch = _epoch;
    if (uid == null || !_desired) return Future.value();
    return _queue(() async {
      if (!_current(uid, epoch) || !_desired) return;
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString(_tokenKey(uid));
      if (previous == token && enabled) return;
      if (previous != null && previous != token) {
        await _write(uid, previous, false);
      }
      await prefs.setString(_tokenKey(uid), token);
      if (!_current(uid, epoch) || !_desired) return;
      await _write(uid, token, true);
      if (_current(uid, epoch) && _desired) enabled = true;
    });
  }

  Future<void> _stop(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey(uid));
    var removed = false, unregistered = false;
    if (token != null) {
      try {
        await _write(uid, token, false);
        await prefs.remove(_tokenKey(uid));
        removed = true;
      } catch (_) {
        /* Retry the stored registration on the next restore. */
      }
    }
    try {
      await access.unregister();
      unregistered = true;
    } catch (_) {
      /* Server removal also stops sends to this installation. */
    }
    if (!removed && !unregistered) {
      throw const LunchException('알림 끄기를 완료하지 못했어요. 연결을 확인하고 다시 시도해 주세요.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
