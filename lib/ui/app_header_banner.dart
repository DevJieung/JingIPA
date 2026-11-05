import 'package:flutter/material.dart';
import 'theme.dart';

/// The top header, which doubles as the banner area on every platform and
/// width (AdMob in the Android/iOS apps, AdSense on the web).
///
/// [AppHeaderBanner.bannerHeight] keeps a 50dp slot, the height of the AdMob
/// standard banner (320x50) and the smallest anchored adaptive banner, so the
/// header no longer changes height when an ad is connected. Until the ad SDK
/// and unit IDs are configured the slot shows [placeholder], the app's own
/// header content, so nothing reads as an ad.
class AppHeaderBanner extends StatelessWidget {
  const AppHeaderBanner({
    required this.placeholder,
    this.trailing = const [],
    super.key,
  });

  /// Height of the banner slot (AdMob/AdSense 320x50 banner).
  static const bannerHeight = 50.0;

  /// Shown in the slot while no ad is connected.
  final Widget placeholder;

  /// Development-only tools (demo/local emulator); never shown in production.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('app-header-banner'),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            key: const Key('app-banner-slot'),
            height: bannerHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              // Large text scales the brand down instead of overflowing.
              child: FittedBox(fit: BoxFit.scaleDown, child: placeholder),
            ),
          ),
        ),
        ...trailing,
      ],
    ),
  );
}
