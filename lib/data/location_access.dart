import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';

class LocationFailure implements Exception {
  const LocationFailure(
    this.message, {
    this.appSettings = false,
    this.locationSettings = false,
  });
  final String message;
  final bool appSettings, locationSettings;
}

class LocationAccess {
  const LocationAccess();
  static const _consentKey = 'meokkiri.nearbyLocationConsent.v1';

  Future<bool> consentGranted() async =>
      (await SharedPreferences.getInstance()).getBool(_consentKey) ?? false;

  Future<void> setConsent(bool granted) async {
    await (await SharedPreferences.getInstance()).setBool(_consentKey, granted);
  }

  /// Checks permission without returning or storing coordinates in the app.
  Future<void> ensurePermission({required bool requestPermission}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        '휴대폰의 위치 기능을 켠 뒤 다시 시도해 주세요.',
        locationSettings: true,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        '위치 권한이 꺼져 있어요. 앱 설정에서 허용하거나 이름으로 검색하세요.',
        appSettings: true,
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const LocationFailure(
        '위치를 허용하지 않았어요. 식당 이름으로 검색할 수 있어요.',
        appSettings: true,
      );
    }
  }

  Future<SearchLocation> current({required bool requestPermission}) async {
    await ensurePermission(requestPermission: requestPermission);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      // Only the consent choice is persisted. Coordinates live in the current search sheet.
      return SearchLocation(p.latitude, p.longitude);
    } catch (_) {
      throw const LocationFailure('현재 위치를 확인하지 못했어요. 다시 시도하거나 이름으로 검색하세요.');
    }
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
