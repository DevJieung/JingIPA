import 'package:flutter/widgets.dart';

/// Rewarded ad shown before the once-per-round 알림 동료 designation.
///
/// AdMob has no app ID or rewarded ad unit ID yet, so [configured] is false:
/// the gate shows no ad, lets the designation through and the UI does not
/// mention ads. Wire the AdMob rewarded ad here once the IDs exist (AdMob does
/// not run on web), and verify the reward on the server before trusting it.
class RewardedAdGate {
  const RewardedAdGate();

  bool get configured => false;

  /// Returns true when the viewer earned the reward (always, until configured).
  Future<bool> show(BuildContext context) async => true;
}
