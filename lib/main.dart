import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'data/app_repository.dart';
import 'data/demo_repository.dart';
import 'data/firebase_repository.dart';
import 'data/local_firebase.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const firebase = bool.fromEnvironment('USE_FIREBASE');
  const local = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  try {
    if (local &&
        (!firebase ||
            const String.fromEnvironment('FIREBASE_PROJECT_ID') !=
                'demo-meokkiri')) {
      throw StateError('Local Firebase requires the demo-meokkiri project.');
    }
    final AppRepository repository;
    if (firebase) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment(
            'FIREBASE_MESSAGING_SENDER_ID',
          ),
          projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
          authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
          storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
          iosBundleId: 'com.meokkiri.meokkiri',
        ),
      );
      if (local) await connectLocalFirebase();
      repository = FirebaseRepository(local: local);
    } else {
      repository = DemoRepository();
    }
    await repository.initialize();
    runApp(MeokkiriApp(repository: repository));
  } catch (error) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('앱을 시작하지 못했어요.\n설정과 네트워크를 확인한 뒤 다시 실행해 주세요.'),
            ),
          ),
        ),
      ),
    );
  }
}
