import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class InviteLinks extends ChangeNotifier {
  String? pending;
  StreamSubscription<Uri>? _subscription;
  bool _disposed = false;
  void _receive(Uri uri) {
    if (_disposed) return;
    if ((uri.scheme == 'meokkiri' && uri.host == 'join') ||
        uri.scheme == 'http' ||
        uri.scheme == 'https') {
      final code = uri.queryParameters['invite'];
      if (code != null && code.isNotEmpty) {
        pending = code;
        notifyListeners();
      }
    }
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      _receive(Uri.base);
      return;
    }
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (_disposed) return;
      if (initial != null) _receive(initial);
      _subscription = links.uriLinkStream.listen(_receive);
    } catch (_) {
      // Links are unavailable on widget-test hosts. Code entry remains supported.
    }
  }

  String? take() {
    final code = pending;
    pending = null;
    return code;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
