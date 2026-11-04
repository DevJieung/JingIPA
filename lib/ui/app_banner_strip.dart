import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'theme.dart';

/// Shown in the native apps only. AdMob has no web SDK, so the web keeps its
/// full content height.
bool get appBannerStripEnabled => !kIsWeb;

/// A quiet strip that stays just above the tab bar on every tab.
///
/// It reserves the standard 320x50 banner area for the planned AdMob banner.
/// Until the SDK and ad unit IDs are configured it shows a small brand line,
/// styled like the app's own surfaces so it does not read as an ad.
class AppBannerStrip extends StatelessWidget {
  const AppBannerStrip({super.key});

  /// Height of the banner area (AdMob standard banner).
  static const bannerHeight = 50.0;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('app-banner-strip'),
    color: paper,
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Container(
      key: const Key('app-banner-slot'),
      height: bannerHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: sageSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
      child: const ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rice_bowl_outlined, size: 18, color: forest),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                '오늘 밥도, 우리끼리.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: forest,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
