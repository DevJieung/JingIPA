import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../data/location_access.dart';
import '../domain/models.dart';
import 'location_consent_dialog.dart';
import 'theme.dart';

class ProfilePermissions extends StatefulWidget {
  const ProfilePermissions({
    required this.repository,
    this.locationAccess = const LocationAccess(),
    super.key,
  });
  final AppRepository repository;
  final LocationAccess locationAccess;
  @override
  State<ProfilePermissions> createState() => _ProfilePermissionsState();
}

class _ProfilePermissionsState extends State<ProfilePermissions>
    with WidgetsBindingObserver {
  bool _locationOn = false, _locationBusy = true;
  LocationFailure? _locationFailure;
  String? _pushError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readLocation());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.repository.refreshPushNotifications());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_locationBusy) {
      unawaited(_readLocation());
    }
  }

  Future<void> _readLocation() async {
    if (mounted) setState(() => _locationBusy = true);
    var consent = false;
    try {
      consent = await widget.locationAccess.consentGranted();
      if (consent) {
        await widget.locationAccess.ensurePermission(requestPermission: false);
      }
      if (mounted) {
        setState(() {
          _locationOn = consent;
          _locationFailure = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _locationOn = consent;
          _locationFailure = error is LocationFailure
              ? error
              : const LocationFailure('위치 권한을 확인하지 못했어요. 다시 시도해 주세요.');
        });
      }
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _setLocation(bool enabled) async {
    if (_locationBusy) return;
    setState(() {
      _locationBusy = true;
      _locationFailure = null;
    });
    try {
      if (enabled) {
        final consent = await widget.locationAccess.consentGranted();
        if (!mounted) return;
        if (!consent && !await confirmLocationConsent(context)) return;
        if (!mounted) return;
        await widget.locationAccess.ensurePermission(requestPermission: true);
      }
      await widget.locationAccess.setConsent(enabled);
      if (mounted) setState(() => _locationOn = enabled);
    } catch (error) {
      if (mounted) {
        setState(
          () => _locationFailure = error is LocationFailure
              ? error
              : const LocationFailure('위치 설정을 바꾸지 못했어요. 다시 시도해 주세요.'),
        );
      }
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _setPush(bool enabled) async {
    setState(() => _pushError = null);
    try {
      await widget.repository.setPushNotifications(enabled);
    } catch (error) {
      if (mounted) {
        setState(
          () => _pushError = error is LunchException
              ? error.message
              : '알림 설정을 바꾸지 못했어요. 연결을 확인하고 다시 시도해 주세요.',
        );
      }
    }
  }

  Future<void> _openSettings({bool locationServices = false}) async {
    final opened = locationServices
        ? await widget.locationAccess.openLocationSettings()
        : await widget.locationAccess.openAppSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('기기 설정이나 브라우저 주소창의 사이트 설정에서 권한을 변경해 주세요.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final repo = widget.repository;
      final pushMessage = _pushError ?? repo.pushNotificationsMessage;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('profile-location-switch'),
            secondary: const Icon(Icons.location_on_outlined, size: 22),
            title: const Text(
              '위치 사용',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _locationOn && _locationFailure != null
                  ? '켜짐 설정 · 기기의 위치 권한을 확인해 주세요'
                  : _locationOn
                  ? '켜짐 · 검색한 식당을 가까운 순으로 정렬해요'
                  : '꺼짐 · 위치 없이 이름으로 검색할 수 있어요',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            value: _locationOn,
            onChanged: _locationBusy ? null : _setLocation,
          ),
          if (_locationFailure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _locationFailure!.message,
                    key: const Key('profile-location-message'),
                    style: const TextStyle(fontSize: 12, color: orange),
                  ),
                  if (!kIsWeb &&
                      (_locationFailure!.appSettings ||
                          _locationFailure!.locationSettings))
                    TextButton(
                      onPressed: () => _openSettings(
                        locationServices: _locationFailure!.locationSettings,
                      ),
                      child: const Text('위치 설정 열기'),
                    ),
                  if (kIsWeb)
                    const Text(
                      '브라우저 주소창의 사이트 설정에서 위치 권한을 확인해 주세요.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            key: const Key('profile-push-switch'),
            secondary: const Icon(Icons.notifications_outlined, size: 22),
            title: const Text(
              'Push 알림',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              !repo.pushNotificationsSupported
                  ? (repo.isDemo || repo.isLocal
                        ? '체험·테스트 환경에서는 기기 알림을 보내지 않아요'
                        : '이 기기·브라우저에서는 Push 알림을 지원하지 않아요')
                  : repo.pushNotificationsEnabled
                  ? '켜짐 · 이 기기에서 라운드 알림을 받아요'
                  : '꺼짐 · 이 기기에서 Push 알림을 받지 않아요',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            value: repo.pushNotificationsEnabled,
            onChanged:
                repo.pushNotificationsBusy ||
                    (!repo.pushNotificationsSupported &&
                        !repo.pushNotificationsEnabled)
                ? null
                : _setPush,
          ),
          if (pushMessage != null || repo.pushNotificationsBlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pushMessage ?? '기기나 브라우저 설정에서 알림을 허용한 뒤 다시 켜 주세요.',
                    key: const Key('profile-push-message'),
                    style: const TextStyle(fontSize: 12, color: orange),
                  ),
                  if (!kIsWeb && repo.pushNotificationsBlocked)
                    TextButton(
                      onPressed: _openSettings,
                      child: const Text('알림 설정 열기'),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
