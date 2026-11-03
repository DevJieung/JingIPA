import 'package:firebase_messaging/firebase_messaging.dart';
import 'push_preferences.dart';

class FirebasePushAccess extends PushAccess {
  FirebasePushAccess({FirebaseMessaging? messaging}) : _injected = messaging;
  final FirebaseMessaging? _injected;
  FirebaseMessaging get _messaging => _injected ?? FirebaseMessaging.instance;
  @override
  Future<PushAuthorization> authorization({
    required bool requestPermission,
  }) async {
    final messaging = _messaging;
    if (!await messaging.isSupported()) return PushAuthorization.unsupported;
    final settings = requestPermission
        ? await messaging.requestPermission()
        : await messaging.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushAuthorization.granted,
      AuthorizationStatus.denied => PushAuthorization.denied,
      _ => PushAuthorization.undetermined,
    };
  }

  @override
  Future<String> register() async {
    final messaging = _messaging;
    final registration = messaging.onRegistered.first.timeout(
      const Duration(seconds: 25),
    );
    final results = await Future.wait<Object?>([
      () async {
        await messaging.setAutoInitEnabled(true);
        await messaging.register();
      }(),
      registration,
    ]);
    return results[1] as String;
  }

  @override
  Future<void> unregister() async {
    final messaging = _messaging;
    await messaging.setAutoInitEnabled(false);
    await messaging.unregister();
  }
}
