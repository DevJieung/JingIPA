import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';

// Web uses one HTTP origin, so forwarding port 8090 also forwards Firebase RPCs.
String get _host => kIsWeb
    ? Uri.base.host
    : const String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');
int _port(int nativePort) => kIsWeb ? Uri.base.port : nativePort;

Future<void> connectLocalFirebase() async {
  if (Firebase.app().options.projectId != 'demo-meokkiri') {
    throw StateError('Local Firebase requires the demo-meokkiri project.');
  }
  await FirebaseAuth.instance.useAuthEmulator(_host, _port(9099));
  if (kIsWeb) {
    // Each browser tab can represent a different coworker.
    await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
  }
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
    webExperimentalForceLongPolling: true,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(_host, _port(8080));
  FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  ).useFunctionsEmulator(_host, _port(5001));
}

Future<void> runLocalAction(
  String action, {
  String? channelId,
  String? actor,
  String? bundleId,
}) async {
  var host = _host;
  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      host == 'localhost') {
    host = '10.0.2.2';
  }
  final response = await http
      .post(
        Uri(
          scheme: 'http',
          host: host,
          port: _port(8090),
          path: '/__local/control',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'channelId': channelId,
          'actor': actor,
          'bundleId': bundleId,
        }),
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw LunchException(data['error'] as String? ?? '로컬 도구를 실행하지 못했어요.');
  }
}
