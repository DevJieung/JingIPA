import 'pods.dart';
export 'pods.dart';

enum RoundPhase { submission, adjusting, finalized, cancelled }

class AppUser {
  const AppUser(this.id, this.name, {this.emoji = defaultRoundEmoji});

  /// The emoji this person uses in one round (waiting room, seats, result
  /// roster). Profiles carry none: everyone starts each round as 🐘.
  final String emoji;
  final String id;
  final String name;
}

class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    this.emoji = '🍽️',
    this.manual = false,
    this.distanceMeters,
  });
  final String id, name, category, address, emoji;
  final bool manual;
  final double? distanceMeters;
  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String? ?? '음식점',
    address: json['address'] as String? ?? '',
    emoji: json['emoji'] as String? ?? '🍽️',
    manual: json['manual'] == true,
    distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'address': address,
    'emoji': emoji,
    'manual': manual,
  };
}

class SearchLocation {
  const SearchLocation(this.latitude, this.longitude);
  final double latitude, longitude;
  Map<String, double> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

class LunchChannel {
  LunchChannel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    required this.inviteCode,
    this.revealMinute = 680,
    this.additionalMinutes = 10,
    this.roundId,
  });
  final String id, name, inviteCode;
  String ownerId;
  final Map<String, String> members;
  int revealMinute, additionalMinutes;
  String? roundId;
  factory LunchChannel.fromJson(Map<String, dynamic> j) => LunchChannel(
    id: j['id'],
    name: j['name'],
    ownerId: j['ownerId'],
    members: {
      for (final id in j['memberIds'] as List? ?? (j['members'] as Map).keys)
        if ((j['members'] as Map).containsKey(id))
          id as String: j['members'][id] as String,
    },
    inviteCode: j['inviteCode'],
    revealMinute: j['revealMinute'] ?? 680,
    additionalMinutes: j['additionalMinutes'] ?? 10,
    roundId: j['roundId'],
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ownerId': ownerId,
    'members': members,
    'memberIds': members.keys.toList(),
    'inviteCode': inviteCode,
    'revealMinute': revealMinute,
    'additionalMinutes': additionalMinutes,
    'roundId': roundId,
  };
}

const personColors = <String, String>{
  'D94B48': '빨강',
  'E58B28': '주황',
  '47966A': '초록',
  '4079D8': '파랑',
  '9862C7': '보라',
  'D26199': '분홍',
};

bool validPersonColor(String value) => RegExp(r'^[0-9A-F]{6}$').hasMatch(value);
String personColorName(String color) => personColors[color] ?? '#$color';

class TokenWallet {
  const TokenWallet({this.balance = 0, this.reserved = 0});
  final int balance, reserved;
  int get available => (balance - reserved).clamp(0, balance);
  factory TokenWallet.fromJson(Map<String, dynamic> j) => TokenWallet(
    balance: (j['balance'] as num? ?? 0).toInt(),
    reserved: (j['reserved'] as num? ?? 0).toInt(),
  );
}

const tokenReservationExplanation =
    '잔여토큰은 예약분을 포함한 전체 보유량이에요. 라운드예약만으로는 잔여토큰이 줄지 않아요. 색상을 지정한 동료 1명당 1개를 예약하고, 최종 확정 때 그중 팟에 참여한 동료 수만큼만 실제 차감해요. 예: 잔여토큰 8개 중 5개를 예약해도 잔여토큰은 8개예요. 2개를 실제 사용하면 잔여토큰은 6개, 라운드예약은 0개가 돼요. 미정은 제외하며, 본인이 마감 때 미참여면 차감은 0개예요.';

class TokenBundle {
  const TokenBundle(
    this.id,
    this.quantity,
    this.priceWon,
    this.discountPercent,
  );
  final String id;
  final int quantity, priceWon, discountPercent;
  factory TokenBundle.fromJson(Map<String, dynamic> j) => TokenBundle(
    j['id'],
    (j['quantity'] as num).toInt(),
    (j['priceWon'] as num).toInt(),
    (j['discountPercent'] as num).toInt(),
  );
}

const defaultTokenBundles = [
  TokenBundle('token_1', 1, 500, 0),
  TokenBundle('token_5', 5, 2250, 10),
  TokenBundle('token_10', 10, 4000, 20),
  TokenBundle('token_30', 30, 10500, 30),
];

/// Resolves the next occurrence in local time, retaining tomorrow after midnight.
DateTime nextRevealTime(DateTime now, int hour, int minute) {
  var result = DateTime(now.year, now.month, now.day, hour, minute);
  if (!result.isAfter(now)) {
    result = DateTime(now.year, now.month, now.day + 1, hour, minute);
  }
  return result;
}

class RestaurantCount {
  const RestaurantCount(
    this.restaurant,
    this.count, {
    this.redCount = 0,
    this.colorCounts = const {},
  });
  final Restaurant restaurant;
  final int count, redCount;
  final Map<String, int> colorCounts;
  Map<String, int> get displayColors =>
      colorCounts.isEmpty && redCount > 0 ? {'D94B48': redCount} : colorCounts;
}

class RoundTransition {
  const RoundTransition({
    required this.id,
    this.version = '',
    required this.phase,
    required this.requiredCount,
    required this.approvedCount,
    required this.required,
    required this.approved,
  });
  final String id, version;
  final RoundPhase phase;
  final int requiredCount, approvedCount;
  final bool required, approved;
  factory RoundTransition.fromJson(Map<String, dynamic> j) => RoundTransition(
    id: j['id'],
    version: j['version'] ?? '',
    phase: RoundPhase.values.byName(j['phase']),
    requiredCount: j['requiredCount'],
    approvedCount: j['approvedCount'],
    required: j['required'] == true,
    approved: j['approved'] == true,
  );
}

class RoundView {
  final bool podMode;
  final List<LunchPod> pods;
  final String? myPodId;
  final int waitingCount;

  /// Anonymous slots: the server sends no member IDs for the waiting room.
  final List<AppUser> waitingMembers;

  /// My emoji in this round only; [defaultRoundEmoji] until I pick another.
  final String myEmoji;
  const RoundView({
    this.podMode = false,
    this.pods = const [],
    this.myPodId,
    this.waitingCount = 0,
    this.waitingMembers = const [],
    this.myEmoji = defaultRoundEmoji,
    this.canJoinFinalPod = false,
    this.finalPodJoined = false,
    required this.id,
    required this.creatorId,
    required this.revealAt,
    required this.endsAt,
    required this.phase,
    required this.myRestaurant,
    required this.withdrawn,
    this.options = const [],
    this.undecidedCount = 0,
    this.undecidedColorCounts = const {},
    this.companions = const [],
    this.finalJoinedIds = const {},
    this.watch,
    this.lateJoinOptions = const [],
    this.lateJoinUsed = false,
    this.tokenEquipped = false,
    this.tokenStatus = 'none',
    this.tokenReservedCount = 0,
    this.tokenChargedCount = 0,
    this.tokenReleasedCount = 0,
    this.tokenSettledAt,
    this.manualControl = false,
    this.cutoffControl = false,
    this.transition,
    this.nextRoundAt,
  });
  final String id, creatorId;
  final bool canJoinFinalPod, finalPodJoined;
  final RoundTransition? transition;
  final DateTime revealAt, endsAt;
  final DateTime? nextRoundAt;
  final RoundPhase phase;
  final Restaurant? myRestaurant;
  final bool withdrawn;
  final List<RestaurantCount> options;
  final int undecidedCount;
  final Map<String, int> undecidedColorCounts;
  final List<AppUser> companions;

  /// Companions who joined my formed pod as a last chance after the cutoff.
  final Set<String> finalJoinedIds;
  final PodWatch? watch;
  final List<RestaurantCount> lateJoinOptions;
  final bool lateJoinUsed;
  final bool manualControl;
  final bool cutoffControl;
  final bool tokenEquipped;
  final String tokenStatus;
  final int tokenReservedCount, tokenChargedCount, tokenReleasedCount;
  final DateTime? tokenSettledAt;
  factory RoundView.fromJson(Map<String, dynamic> j) => RoundView(
    nextRoundAt: j['nextRoundAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (j['nextRoundAt'] as num).toInt(),
          ),
    podMode: j['podMode'] == true,
    pods: (j['pods'] as List? ?? [])
        .map((p) => LunchPod.fromJson(Map<String, dynamic>.from(p)))
        .toList(),
    myPodId: j['myPodId'],
    myEmoji: roundEmojis.contains(j['myEmoji'])
        ? j['myEmoji'] as String
        : defaultRoundEmoji,
    canJoinFinalPod: j['canJoinFinalPod'] == true,
    finalPodJoined: j['finalPodJoined'] == true,
    waitingCount: j['waitingCount'] ?? 0,
    waitingMembers: (j['waitingMembers'] as List? ?? [])
        .map(
          (p) => AppUser(
            p['id'],
            p['name'] ?? '',
            emoji: p['emoji'] ?? defaultRoundEmoji,
          ),
        )
        .toList(),
    lateJoinUsed: j['lateJoinUsed'] == true,
    lateJoinOptions: (j['lateJoinOptions'] as List? ?? [])
        .map(
          (e) => RestaurantCount(
            Restaurant.fromJson(Map<String, dynamic>.from(e['restaurant'])),
            (e['count'] as num).toInt(),
          ),
        )
        .toList(),
    transition: j['transition'] == null
        ? null
        : RoundTransition.fromJson(Map<String, dynamic>.from(j['transition'])),
    tokenEquipped: j['tokenEquipped'] == true,
    tokenStatus: j['tokenStatus'] ?? 'none',
    tokenReservedCount: (j['tokenReservedCount'] as num? ?? 0).toInt(),
    tokenChargedCount: (j['tokenChargedCount'] as num? ?? 0).toInt(),
    tokenReleasedCount: (j['tokenReleasedCount'] as num? ?? 0).toInt(),
    tokenSettledAt: j['tokenSettledAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (j['tokenSettledAt'] as num).toInt(),
          ),
    manualControl: j['manualControl'] == true,
    cutoffControl: j['cutoffControl'] == true,
    id: j['id'],
    creatorId: j['creatorId'],
    revealAt: DateTime.fromMillisecondsSinceEpoch(
      (j['revealAt'] as num).toInt(),
    ),
    endsAt: DateTime.fromMillisecondsSinceEpoch((j['endsAt'] as num).toInt()),
    phase: RoundPhase.values.byName(j['phase']),
    myRestaurant: j['myRestaurant'] == null
        ? null
        : Restaurant.fromJson(
            Map<String, dynamic>.from(j['myRestaurant'] as Map),
          ),
    withdrawn: j['withdrawn'] == true,
    undecidedCount: (j['undecidedCount'] as num? ?? 0).toInt(),
    undecidedColorCounts: (j['undecidedColorCounts'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    ),
    options: (j['options'] as List? ?? [])
        .map(
          (e) => RestaurantCount(
            Restaurant.fromJson(
              Map<String, dynamic>.from(e['restaurant'] as Map),
            ),
            (e['count'] as num).toInt(),
            redCount: (e['redCount'] as num? ?? 0).toInt(),
            colorCounts: (e['colorCounts'] as Map? ?? {}).map(
              (k, v) => MapEntry(k as String, (v as num).toInt()),
            ),
          ),
        )
        .toList(),
    companions: (j['companions'] as List? ?? [])
        .map(
          (e) => AppUser(
            e['id'],
            e['name'],
            emoji: e['emoji'] ?? defaultRoundEmoji,
          ),
        )
        .toList(),
    finalJoinedIds: {
      for (final e in j['companions'] as List? ?? [])
        if (e['finalJoined'] == true) e['id'] as String,
    },
    watch: j['watch'] == null
        ? null
        : PodWatch.fromJson(Map<String, dynamic>.from(j['watch'] as Map)),
  );
}

/// My 알림 동료 for the current round. Only I receive it; [here] is true
/// while recruiting when that person sits in my pod (the pod shows a bell).
class PodWatch {
  const PodWatch({
    required this.id,
    required this.name,
    this.emoji = '🐘',
    this.here = false,
  });
  final String id, name, emoji;
  final bool here;
  factory PodWatch.fromJson(Map<String, dynamic> j) => PodWatch(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    emoji: j['emoji'] as String? ?? '🐘',
    here: j['here'] == true,
  );
}

class LunchException implements Exception {
  const LunchException(this.message);
  final String message;
  @override
  String toString() => message;
}

String roundCooldownMessage(DateTime availableAt, DateTime now) {
  final milliseconds = availableAt.difference(now).inMilliseconds;
  final seconds = milliseconds <= 0 ? 0 : (milliseconds + 999) ~/ 1000;
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')} 뒤에 새로 오픈 가능해요';
}

class RoundCooldownException extends LunchException {
  RoundCooldownException(this.availableAt, DateTime now)
    : super(roundCooldownMessage(availableAt, now));
  final DateTime availableAt;
}

/// Private state. A production client receives only a sanitized [RoundView].
class LunchRound {
  LunchRound({
    required this.id,
    required this.creatorId,
    required this.revealAt,
    required this.endsAt,
    Map<String, String>? selections,
    Set<String>? withdrawn,
    List<String>? optionIds,
    this.manualControl = false,
    this.cutoffControl = false,
    this.eligibleMemberIds,
    this.manualPhase = RoundPhase.submission,
    this.frozen = false,
    this.cancelled = false,
    this.pendingTransition,
    Map<String, String>? tokenStatuses,
    Map<String, Map<String, String>>? tokenColors,
    Map<String, Map<String, int>>? tokenReceipts,
    this.finalSelections,
    Map<String, String>? lateJoins,
  }) : selections = selections ?? {},
       withdrawn = withdrawn ?? {},
       optionIds = optionIds ?? [],
       tokenStatuses = tokenStatuses ?? {},
       tokenColors = tokenColors ?? {},
       lateJoins = lateJoins ?? {},
       tokenReceipts = tokenReceipts ?? {};
  final String id, creatorId;
  DateTime revealAt, endsAt;
  final Map<String, String> selections;
  final Set<String> withdrawn;
  final List<String> optionIds;
  bool manualControl;
  bool cutoffControl;
  List<String>? eligibleMemberIds;
  RoundPhase manualPhase;
  bool frozen, cancelled;
  Map<String, dynamic>? pendingTransition;
  final Map<String, String> tokenStatuses;
  final Map<String, Map<String, String>> tokenColors;
  final Map<String, Map<String, int>> tokenReceipts;
  Map<String, String>? finalSelections;
  final Map<String, String> lateJoins;
  Set<String> approvalMembers(LunchChannel channel) => {
    ...selections.keys,
    ...tokenStatuses.keys.where((uid) => tokenStatuses[uid] == 'reserved'),
  }.intersection(channel.members.keys.toSet()).difference(withdrawn);

  void reconcileTransition(
    LunchChannel channel,
    DateTime now, {
    String? changedUser,
  }) {
    final pending = pendingTransition;
    if (pending == null) return;
    if (phaseAt(now).name != pending['phase']) {
      pendingTransition = null;
      return;
    }
    final required = approvalMembers(channel);
    final approved = Set<String>.from(
      pending['approvedIds'],
    ).intersection(required)..remove(changedUser);
    pending['requiredIds'] = required.toList();
    pending['approvedIds'] = approved.toList();
    if (required.difference(approved).isEmpty) {
      if (phaseAt(now) == RoundPhase.submission) {
        optionIds
          ..clear()
          ..addAll(selections.values.toSet());
        frozen = true;
        manualPhase = RoundPhase.adjusting;
      } else {
        manualPhase = RoundPhase.finalized;
        finalSelections = Map.from(selections);
      }
      pendingTransition = null;
    }
  }

  RoundPhase phaseAt(DateTime now) => cancelled
      ? RoundPhase.cancelled
      : manualControl
      ? manualPhase
      : !now.isBefore(endsAt)
      ? RoundPhase.finalized
      : !now.isBefore(revealAt)
      ? RoundPhase.adjusting
      : RoundPhase.submission;

  void synchronize(DateTime now) {
    if (phaseAt(now) == RoundPhase.finalized) {
      finalSelections ??= Map.from(selections);
    }
    if (!manualControl && !cancelled && !frozen && !now.isBefore(revealAt)) {
      optionIds.addAll(selections.values.toSet());
      frozen = true;
    }
  }

  void _checkMember(String uid, LunchChannel channel) {
    if (!channel.members.containsKey(uid)) {
      throw const LunchException('이 채널의 구성원만 참여할 수 있어요.');
    }
  }

  void _checkOpen(DateTime now) {
    final phase = phaseAt(now);
    if (phase == RoundPhase.cancelled || phase == RoundPhase.finalized) {
      throw const LunchException('이미 끝난 라운드예요.');
    }
  }

  void choose(
    String uid,
    String restaurantId,
    LunchChannel channel,
    Map<String, Restaurant> catalog,
    DateTime now,
  ) {
    _checkMember(uid, channel);
    _checkOpen(now);
    synchronize(now);
    if (!catalog.containsKey(restaurantId)) {
      throw const LunchException('식당을 다시 검색해 주세요.');
    }
    if (frozen && !optionIds.contains(restaurantId)) {
      optionIds.add(restaurantId);
    }
    selections[uid] = restaurantId;
    withdrawn.remove(uid);
  }

  void withdraw(String uid, LunchChannel channel, DateTime now) {
    _checkMember(uid, channel);
    _checkOpen(now);
    if (phaseAt(now) == RoundPhase.adjusting) {
      throw const LunchException('Round2에서는 빠질 수 없어요. 식당 변경만 가능해요.');
    }
    synchronize(now);
    selections.remove(uid);
    withdrawn.add(uid);
    final others = channel.members.keys.where((id) => id != creatorId).toList();
    if (uid == creatorId ||
        (others.isNotEmpty && others.every(withdrawn.contains)) ||
        channel.members.keys.every(withdrawn.contains)) {
      cancelled = true;
    }
  }

  void cancel(String uid, LunchChannel channel, DateTime now) {
    _checkMember(uid, channel);
    _checkOpen(now);
    if (phaseAt(now) == RoundPhase.adjusting) {
      throw const LunchException('Round2에서는 라운드를 취소할 수 없어요. 최종 확정을 진행해 주세요.');
    }
    if (uid != creatorId) {
      throw const LunchException('라운드를 연 사람만 전체 취소할 수 있어요.');
    }
    cancelled = true;
  }

  List<String> _lateJoinTargets(
    String uid,
    LunchChannel channel,
    DateTime now,
  ) {
    if (phaseAt(now) != RoundPhase.finalized ||
        !channel.members.containsKey(uid) ||
        !(eligibleMemberIds ?? channel.members.keys).contains(uid) ||
        withdrawn.contains(uid) ||
        lateJoins.containsKey(uid)) {
      return [];
    }
    final original = finalSelections ?? selections;
    final mine = original[uid];
    if (mine != null && original.values.where((id) => id == mine).length != 1) {
      return [];
    }
    return optionIds
        .where(
          (id) =>
              id != mine &&
              original.values.where((place) => place == id).length >= 2 &&
              selections.entries
                      .where(
                        (e) =>
                            e.value == id && channel.members.containsKey(e.key),
                      )
                      .length >=
                  2,
        )
        .toList();
  }

  void joinFinalParty(
    String uid,
    String restaurantId,
    LunchChannel channel,
    DateTime now,
  ) {
    _checkMember(uid, channel);
    if (phaseAt(now) != RoundPhase.finalized) {
      throw const LunchException('최종 확정 뒤 혼밥 또는 미정인 경우에만 합류할 수 있어요.');
    }
    synchronize(now);
    if (lateJoins[uid] == restaurantId) return;
    if (!_lateJoinTargets(uid, channel, now).contains(restaurantId)) {
      throw const LunchException('혼밥·미정으로 마감한 구성원은 2명 이상 팟에 한 번만 합류할 수 있어요.');
    }
    lateJoins[uid] = restaurantId;
    selections[uid] = restaurantId;
  }

  RoundView view(
    String uid,
    LunchChannel channel,
    Map<String, Restaurant> catalog,
    DateTime now, {
    Set<String> redTargets = const {},
    bool premiumActive = false,
    Map<String, String> colorTargets = const {},
  }) {
    _checkMember(uid, channel);
    synchronize(now);
    final phase = phaseAt(now);
    final mine = selections[uid];
    final showCounts =
        phase == RoundPhase.adjusting || phase == RoundPhase.finalized;
    final undecided = phase == RoundPhase.adjusting
        ? channel.members.keys
              .where(
                (id) => !selections.containsKey(id) && !withdrawn.contains(id),
              )
              .toSet()
        : <String>{};
    return RoundView(
      manualControl: manualControl,
      cutoffControl: cutoffControl,
      tokenEquipped: tokenStatuses[uid] == 'reserved',
      tokenStatus: tokenStatuses[uid] ?? 'none',
      tokenReservedCount: tokenReceipts[uid]?['reservedCount'] ?? 0,
      tokenChargedCount: tokenReceipts[uid]?['chargedCount'] ?? 0,
      tokenReleasedCount: tokenReceipts[uid]?['releasedCount'] ?? 0,
      tokenSettledAt: tokenReceipts[uid]?['settledAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              tokenReceipts[uid]!['settledAt']!,
            ),
      id: id,
      creatorId: creatorId,
      transition: pendingTransition == null
          ? null
          : RoundTransition(
              id: pendingTransition!['id'],
              phase: RoundPhase.values.byName(pendingTransition!['phase']),
              requiredCount: (pendingTransition!['requiredIds'] as List).length,
              approvedCount: (pendingTransition!['approvedIds'] as List).length,
              required: (pendingTransition!['requiredIds'] as List).contains(
                uid,
              ),
              approved: (pendingTransition!['approvedIds'] as List).contains(
                uid,
              ),
            ),
      revealAt: revealAt,
      endsAt: endsAt,
      phase: phase,
      lateJoinUsed: lateJoins.containsKey(uid),
      lateJoinOptions: _lateJoinTargets(uid, channel, now)
          .map(
            (id) => RestaurantCount(
              catalog[id]!,
              selections.entries
                  .where(
                    (e) => e.value == id && channel.members.containsKey(e.key),
                  )
                  .length,
            ),
          )
          .toList(),
      myRestaurant: mine == null ? null : catalog[mine],
      withdrawn: withdrawn.contains(uid),
      undecidedCount: undecided.length,
      undecidedColorCounts: premiumActive
          ? {
              for (final color in colorTargets.values.toSet().where(
                validPersonColor,
              ))
                color: undecided
                    .where((id) => id != uid && colorTargets[id] == color)
                    .length,
            }
          : {},
      options: showCounts
          ? optionIds
                .map(
                  (id) => RestaurantCount(
                    catalog[id]!,
                    selections.values
                        .where((selected) => selected == id)
                        .length,
                    colorCounts: premiumActive && phase == RoundPhase.adjusting
                        ? {
                            for (final color
                                in colorTargets.values.toSet().where(
                                  validPersonColor,
                                ))
                              color: selections.entries
                                  .where(
                                    (e) =>
                                        e.key != uid &&
                                        channel.members.containsKey(e.key) &&
                                        colorTargets[e.key] == color &&
                                        e.value == id,
                                  )
                                  .length,
                          }
                        : {},
                    redCount: premiumActive && phase == RoundPhase.adjusting
                        ? selections.entries
                              .where(
                                (e) =>
                                    e.key != uid &&
                                    channel.members.containsKey(e.key) &&
                                    redTargets.contains(e.key) &&
                                    e.value == id,
                              )
                              .length
                        : 0,
                  ),
                )
                .toList()
          : [],
      companions: phase == RoundPhase.finalized && mine != null
          ? selections.entries
                .where(
                  (e) =>
                      e.value == mine &&
                      e.key != uid &&
                      channel.members.containsKey(e.key),
                )
                .map((e) => AppUser(e.key, channel.members[e.key] ?? '탈퇴한 동료'))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'creatorId': creatorId,
    'revealAt': revealAt.millisecondsSinceEpoch,
    'endsAt': endsAt.millisecondsSinceEpoch,
    'selections': selections,
    'withdrawn': withdrawn.toList(),
    'optionIds': optionIds,
    'manualControl': manualControl,
    'cutoffControl': cutoffControl,
    'eligibleMemberIds': eligibleMemberIds,
    'manualPhase': manualPhase.name,
    'frozen': frozen,
    'cancelled': cancelled,
    'pendingTransition': pendingTransition,
    'tokenStatuses': tokenStatuses,
    'tokenColors': tokenColors,
    'tokenReceipts': tokenReceipts,
    'finalSelections': finalSelections,
    'lateJoins': lateJoins,
  };
  factory LunchRound.fromJson(Map<String, dynamic> j) => LunchRound(
    finalSelections: j['finalSelections'] == null
        ? null
        : Map<String, String>.from(j['finalSelections']),
    lateJoins: Map<String, String>.from(j['lateJoins'] as Map? ?? {}),
    id: j['id'],
    creatorId: j['creatorId'],
    revealAt: DateTime.fromMillisecondsSinceEpoch(j['revealAt']),
    endsAt: DateTime.fromMillisecondsSinceEpoch(j['endsAt']),
    selections: Map<String, String>.from(j['selections'] as Map),
    withdrawn: Set<String>.from(j['withdrawn'] as List),
    optionIds: List<String>.from(j['optionIds'] as List),
    manualControl: j['manualControl'] == true,
    cutoffControl: j['cutoffControl'] == true,
    eligibleMemberIds: (j['eligibleMemberIds'] as List?)?.cast<String>(),
    manualPhase: RoundPhase.values.byName(j['manualPhase'] ?? 'submission'),
    frozen: j['frozen'] == true,
    cancelled: j['cancelled'] == true,
    pendingTransition: j['pendingTransition'] == null
        ? null
        : Map<String, dynamic>.from(j['pendingTransition']),
    tokenStatuses: Map<String, String>.from(j['tokenStatuses'] as Map? ?? {}),
    tokenReceipts: (j['tokenReceipts'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, Map<String, int>.from(v as Map)),
    ),
    tokenColors: (j['tokenColors'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, Map<String, String>.from(v as Map)),
    ),
  );
}
