import 'package:flutter/foundation.dart';
import '../domain/models.dart';

enum SessionStatus {
  restoring,
  signedOut,
  loadingProfile,
  needsProfile,
  ready,
  failed,
}

enum LoadStatus { idle, loading, ready, failed }

abstract class AppRepository extends ChangeNotifier {
  AppUser? get user;
  SessionStatus get sessionStatus => user == null
      ? SessionStatus.signedOut
      : user!.name.isEmpty
      ? SessionStatus.needsProfile
      : SessionStatus.ready;
  LoadStatus get channelsStatus => LoadStatus.ready;
  LoadStatus roundStatusFor(String channelId) => LoadStatus.ready;
  String? roundErrorFor(String channelId) => null;
  String? get selectedChannelId => null;
  Future<void> selectChannel(String channelId) async {}
  Future<void> loadChannelSummaries() async {}
  Future<void> retrySession() => refresh();
  LoadStatus get attendanceStatus => LoadStatus.ready;
  Future<void> loadAttendance({bool force = false}) async {}
  LoadStatus get favoritesStatus => LoadStatus.ready;
  Future<void> loadFavorites({bool force = false}) async {}
  LoadStatus historyStatusFor(String channelId) => LoadStatus.ready;
  Future<void> loadHistory(String channelId, {bool force = false}) async {}
  Future<void> updateProfile(String name, String emoji) =>
      throw const LunchException('프로필을 변경할 수 없어요.');
  Attendance get attendance => const Attendance();
  Future<void> updateEmoji(String emoji) =>
      throw const LunchException('이모지를 변경할 수 없어요.');
  Future<void> startPodRound(
    String channelId,
    DateTime endsAt,
    List<String> expectedMemberIds,
  ) => throw const LunchException('팟 라운드를 지원하지 않아요.');
  Future<void> createPod(
    String channelId,
    String name,
    int minimum,
    String requestId, {
    String? restaurantId,
    String? restaurantText,
    TemporaryRestaurant? temporaryRestaurant,
  }) => throw const LunchException('팟 생성을 지원하지 않아요.');
  Future<void> joinPod(String channelId, String podId) =>
      throw const LunchException('팟 참여를 지원하지 않아요.');
  Future<void> joinFinalPod(String channelId, String podId) =>
      throw const LunchException('최종 팟 선택을 지원하지 않아요.');
  Future<void> leavePod(String channelId) =>
      throw const LunchException('대기실 이동을 지원하지 않아요.');

  /// The creator removes a pod nobody else is in; if they sat in it alone they
  /// return to the waiting room.
  Future<void> deletePod(String channelId, String podId) =>
      throw const LunchException('팟 삭제를 지원하지 않아요.');
  Future<void> setPodWatch(String channelId, String targetId) =>
      throw const LunchException('알림 동료 지정을 지원하지 않아요.');
  Future<void> changePodDeadline(String channelId, DateTime endsAt) =>
      throw const LunchException('마감을 변경할 수 없어요.');
  List<LunchChannel> get channels;
  bool get isDemo;
  bool get isLocal => false;
  bool get isGuest => false;
  Future<void> signInGuest(String name, String code) =>
      throw const LunchException('비회원 참여를 지원하지 않는 환경이에요.');
  Future<void> signInLocal(String actor) =>
      throw UnsupportedError('Local only');
  Future<void> localAction(String action, {String? channelId}) =>
      throw UnsupportedError('Local only');
  bool get premiumActive;
  TokenWallet get wallet;
  List<TokenBundle> get tokenBundles => defaultTokenBundles;
  bool get billingAvailable => false;
  bool get storePurchasesSupported => false;
  bool get billingBusy => false;
  String? get billingMessage => null;
  String get billingStoreLabel => '스토어';
  String? billingPrice(String bundleId) => null;
  int billingDiscountPercent(TokenBundle bundle) => 0;
  bool canPurchaseBundle(String bundleId) => billingAvailable;
  Future<void> retryStorePurchases() async {}
  bool get isAdmin => false;
  List<Restaurant> get favorites;
  bool isFavorite(String id) => favorites.any((r) => r.id == id);
  Map<String, String> colorsFor(String channelId);
  Future<void> saveColors(String channelId, Map<String, String> colors);
  Future<void> equipToken(String channelId, bool enabled);
  Future<void> purchaseTokens(String bundleId);
  Future<void> sendCustomerMessage(String message, String requestId);
  Future<List<Map<String, dynamic>>> customerMessages({bool admin = false});
  Future<void> setFavorite(Restaurant restaurant, bool saved);
  Future<Restaurant> addManualRestaurant(
    String name,
    String address,
    String category, {
    bool report = false,
    bool saveToFavorites = true,
  });
  Future<void> reportRestaurant(
    String name,
    String address,
    String category, {
    String note = '',
  });
  Future<List<Map<String, dynamic>>> restaurantReports({bool admin = false});
  Future<void> resolveReport(Map<String, dynamic> data);
  Set<String> redTargetsFor(String channelId);
  Future<void> saveRedTargets(String channelId, Set<String> targets);
  DateTime get now;
  String? get connectionError;
  RoundView? roundFor(String channelId);
  DateTime? nextRoundAtFor(String channelId) {
    final round = roundFor(channelId);
    return round?.nextRoundAt ??
        (round?.phase == RoundPhase.finalized
            ? round!.endsAt.add(const Duration(minutes: 5))
            : null);
  }

  List<RoundView> roundHistoryFor(String channelId) => const [];
  Future<void> initialize();
  Future<void> enterDemo();
  Future<void> signInGoogle();
  Future<void> signInApple();
  Future<void> signOut();
  Future<void> updateName(String name);
  Future<void> deleteAccount();
  Future<void> refresh();
  Future<void> createChannel(String name);
  Future<void> joinChannel(String code);
  String get channelJoinMessage => '채널에 들어왔어요.';
  Future<void> leaveChannel(String channelId);
  Future<void> removeChannelMember(String channelId, String memberId);
  Future<void> saveDefaults(
    String channelId,
    int revealMinute,
    int additionalMinutes,
  );
  Future<void> startRound(
    String channelId,
    DateTime revealAt,
    int additionalMinutes, {
    List<String>? expectedMemberIds,
  });
  Future<List<Restaurant>> search(String query, {SearchLocation? near});
  Future<void> choose(String channelId, String restaurantId);
  Future<void> joinFinalParty(String channelId, String restaurantId) =>
      throw const LunchException('마지막 합류를 지원하지 않는 환경이에요.');
  Future<void> withdraw(String channelId);
  Future<void> cancelRound(String channelId);
  Future<void> advanceRound(String channelId, RoundPhase expectedPhase);
  Future<void> setRoundCutoffs(
    String channelId,
    RoundPhase expectedPhase,
    DateTime revealAt,
    DateTime endsAt,
  );
  Future<void> approveRoundTransition(
    String channelId,
    String transitionId,
    RoundPhase phase,
  );
  bool get pushNotificationsEnabled => false;
  bool get pushNotificationsBusy => false;
  bool get pushNotificationsSupported => false;
  bool get pushNotificationsBlocked => false;
  String? get pushNotificationsMessage => null;
  Future<void> setPushNotifications(bool enabled) async {}
  Future<void> refreshPushNotifications() async {}
}
