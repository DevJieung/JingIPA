import 'models.dart';

const profileEmojis = [
  '🐘',
  '🐼',
  '🐱',
  '🐻',
  '🐶',
  '🐰',
  '🦊',
  '🐯',
  '🐸',
  '🐨',
  '🐧',
  '🦁',
  '🐹',
  '🐵',
  '🦄',
  '🐷',
  '🐣',
  '🦉',
  '🐢',
  '🐳',
  '🍀',
  '🌻',
  '🍑',
  '🥑',
];

class Attendance {
  const Attendance({this.total = 0, this.attended = 0});
  final int total, attended;
  int? get rate => total == 0 ? null : (100 * attended / total).round();
  String get badge => total >= 5 && attended * 100 >= total * 90
      ? '프로참석러'
      : attended > 0
      ? '함께 먹는 중'
      : '첫 만남 준비 중';
  factory Attendance.fromJson(Map<String, dynamic> j) =>
      Attendance(total: j['total'] ?? 0, attended: j['attended'] ?? 0);
}

class TemporaryRestaurant {
  const TemporaryRestaurant(this.name, this.address);
  final String name, address;
  factory TemporaryRestaurant.fromJson(Map<String, dynamic> j) =>
      TemporaryRestaurant(j['name'], j['address']);
  Map<String, dynamic> toJson() => {'name': name, 'address': address};
}

class LunchPod {
  const LunchPod({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.minimum,
    this.count = 0,
    this.restaurant,
    this.restaurantText,
    this.temporaryRestaurant,
    this.finalFormed,
    this.colorCounts = const {},
    this.occupantEmojis = const [],
    this.ownSeatIndex,
    this.createdByMe = false,
  });
  final String id, name, creatorId;
  final int minimum, count;
  final Restaurant? restaurant;
  final String? restaurantText;
  final TemporaryRestaurant? temporaryRestaurant;
  final bool? finalFormed;
  final Map<String, int> colorCounts;
  final List<String> occupantEmojis;
  final int? ownSeatIndex;

  /// True only in the requester's own view of pods they created. The server
  /// never sends creator UIDs before the cutoff.
  final bool createdByMe;
  bool get formed => finalFormed ?? count >= minimum;
  factory LunchPod.fromJson(Map<String, dynamic> j) => LunchPod(
    id: j['id'],
    name: j['name'],
    creatorId: j['creatorId'] ?? '',
    minimum: j['minimum'],
    count: j['count'] ?? 0,
    occupantEmojis: List<String>.from(j['occupantEmojis'] ?? const []),
    ownSeatIndex: (j['ownSeatIndex'] as num?)?.toInt(),
    createdByMe: j['createdByMe'] == true,
    restaurantText: j['restaurantText'],
    temporaryRestaurant: j['temporaryRestaurant'] == null
        ? null
        : TemporaryRestaurant.fromJson(
            Map<String, dynamic>.from(j['temporaryRestaurant']),
          ),
    finalFormed: j['formed'],
    colorCounts: Map<String, int>.from(j['colorCounts'] ?? {}),
    restaurant: j['restaurant'] == null
        ? null
        : Restaurant.fromJson(Map<String, dynamic>.from(j['restaurant'])),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'creatorId': creatorId,
    'minimum': minimum,
    'count': count,
    'occupantEmojis': occupantEmojis,
    'ownSeatIndex': ownSeatIndex,
    'createdByMe': createdByMe,
    'restaurant': restaurant?.toJson(),
    'restaurantText': restaurantText,
    'temporaryRestaurant': temporaryRestaurant?.toJson(),
  };
}

/// Offline state follows the production single deadline and snapshots attendance once.
class PodRoundData {
  PodRoundData({
    required this.id,
    required this.creatorId,
    required this.endsAt,
    required this.eligible,
    this.channelId,
    Map<String, LunchPod>? pods,
    Map<String, String>? selections,
    this.attendance,
    this.cancelled = false,
    this.cancelledAt,
    this.finalSelections,
    this.formedPodIds,
    Map<String, String>? finalJoins,
    Map<String, List<String>>? podMemberOrder,
    Map<String, String>? watches,
    List<String>? deletedPodIds,
  }) : pods = pods ?? {},
       selections = selections ?? {},
       finalJoins = finalJoins ?? {},
       podMemberOrder = podMemberOrder ?? {},
       watches = watches ?? {},
       deletedPodIds = deletedPodIds ?? [];
  final String id, creatorId;
  String? channelId;
  DateTime endsAt;
  final List<String> eligible;
  final Map<String, LunchPod> pods;
  final Map<String, String> selections;
  final Map<String, List<String>> podMemberOrder;
  Map<String, bool>? attendance;
  Map<String, String>? finalSelections;
  List<String>? formedPodIds;
  final Map<String, String> finalJoins;

  /// Designator → 알림 동료, one per member per round.
  final Map<String, String> watches;

  /// Pods their creators deleted; retried create/delete requests stay no-ops.
  final List<String> deletedPodIds;
  bool cancelled;
  DateTime? cancelledAt;
  bool open(DateTime now) => !cancelled && now.isBefore(endsAt);
  List<String> orderedMembers(String podId) {
    final current = selections.entries
        .where((entry) => entry.value == podId)
        .map((entry) => entry.key)
        .toSet();
    final saved = (podMemberOrder[podId] ?? const <String>[])
        .where(current.contains)
        .toSet()
        .toList();
    final missing = current.difference(saved.toSet()).toList()..sort();
    final creator = pods[podId]?.creatorId;
    if (creator != null && missing.remove(creator)) missing.insert(0, creator);
    return [...saved, ...missing];
  }

  void assignPod(String uid, String? podId) {
    for (final id in pods.keys) {
      podMemberOrder[id] = orderedMembers(id);
    }
    if (podId == null) {
      selections.remove(uid);
    } else {
      selections[uid] = podId;
    }
    for (final id in pods.keys) {
      podMemberOrder[id] = orderedMembers(id);
    }
  }

  void settle(DateTime now) {
    if (!open(now) && !cancelled) {
      finalSelections ??= Map.of(selections);
      formedPodIds ??= [
        for (final p in pods.values)
          if (finalSelections!.values.where((v) => v == p.id).length >=
              p.minimum)
            p.id,
      ];
      attendance ??= {
        for (final uid in eligible)
          uid: formedPodIds!.contains(finalSelections![uid]),
      };
    }
  }

  RoundView view(
    String uid,
    LunchChannel channel,
    DateTime now, {
    LunchRound? tokens,
  }) {
    settle(now);
    final finalized = !open(now) && !cancelled;
    LunchPod projectPod(LunchPod p) {
      final occupants = orderedMembers(p.id);
      final ownIndex = occupants.indexOf(uid);
      return LunchPod(
        id: p.id,
        name: p.name,
        creatorId: p.creatorId,
        minimum: p.minimum,
        restaurant: p.restaurant,
        restaurantText: p.restaurantText,
        temporaryRestaurant: p.temporaryRestaurant,
        finalFormed: finalized ? formedPodIds!.contains(p.id) : null,
        count: occupants.length,
        occupantEmojis: [
          for (final person in occupants) channel.memberEmojis[person] ?? '🐘',
        ],
        ownSeatIndex: ownIndex < 0 ? null : ownIndex,
        createdByMe: p.creatorId == uid,
      );
    }

    final mine = selections[uid];
    final companions = open(now) || mine == null || !pods.containsKey(mine)
        ? <AppUser>[]
        : [
            for (final person in orderedMembers(mine))
              if (person != uid && channel.members.containsKey(person))
                AppUser(
                  person,
                  channel.members[person]!,
                  emoji: channel.memberEmojis[person] ?? '🐘',
                ),
          ];
    return RoundView(
      id: id,
      creatorId: creatorId,
      revealAt: endsAt,
      endsAt: endsAt,
      nextRoundAt: cancelled
          ? cancelledAt?.add(const Duration(minutes: 5))
          : open(now)
          ? null
          : endsAt.add(const Duration(minutes: 5)),
      phase: cancelled
          ? RoundPhase.cancelled
          : open(now)
          ? RoundPhase.submission
          : RoundPhase.finalized,
      myRestaurant: null,
      withdrawn: false,
      podMode: true,
      cutoffControl: true,
      pods: [for (final p in pods.values) projectPod(p)],
      myPodId: selections[uid],
      canJoinFinalPod:
          finalized &&
          formedPodIds!.isNotEmpty &&
          !formedPodIds!.contains(finalSelections![uid]) &&
          !finalJoins.containsKey(uid),
      finalPodJoined: finalJoins.containsKey(uid),
      waitingMembers: [
        for (final e in channel.members.entries)
          if (!selections.containsKey(e.key) ||
              (finalized && !formedPodIds!.contains(selections[e.key])))
            AppUser(e.key, '', emoji: channel.memberEmojis[e.key] ?? '🐘'),
      ],
      waitingCount: channel.members.keys
          .where(
            (id) =>
                !selections.containsKey(id) ||
                (finalized && !formedPodIds!.contains(selections[id])),
          )
          .length,
      // Seat order, like the server; last-chance joiners are marked 합류.
      companions: companions,
      finalJoinedIds: {
        for (final person in companions)
          if (finalJoins[person.id] == selections[uid]) person.id,
      },
      watch: switch (watches[uid]) {
        final target? when channel.members.containsKey(target) => PodWatch(
          id: target,
          name: channel.members[target]!,
          emoji: channel.memberEmojis[target] ?? '🐘',
          here: open(now) && mine != null && selections[target] == mine,
        ),
        _ => null,
      },
    );
  }

  factory PodRoundData.fromJson(Map<String, dynamic> j) => PodRoundData(
    id: j['id'],
    channelId: j['channelId'],
    creatorId: j['creatorId'] ?? '',
    endsAt: DateTime.fromMillisecondsSinceEpoch(j['endsAt']),
    eligible: List<String>.from(j['eligible']),
    pods: {
      for (final p in j['pods'])
        p['id'] as String: LunchPod.fromJson(Map<String, dynamic>.from(p)),
    },
    selections: Map<String, String>.from(j['selections']),
    podMemberOrder: (j['podMemberOrder'] as Map? ?? {}).map(
      (key, value) => MapEntry(key as String, List<String>.from(value)),
    ),
    attendance: j['attendance'] == null
        ? null
        : Map<String, bool>.from(j['attendance']),
    finalSelections: j['finalSelections'] == null
        ? null
        : Map<String, String>.from(j['finalSelections']),
    formedPodIds: j['formedPodIds'] == null
        ? null
        : List<String>.from(j['formedPodIds']),
    finalJoins: Map<String, String>.from(j['finalJoins'] ?? {}),
    watches: Map<String, String>.from(j['watches'] ?? {}),
    deletedPodIds: List<String>.from(j['deletedPodIds'] ?? const []),
    cancelled: j['cancelled'] == true,
    cancelledAt: j['cancelledAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (j['cancelledAt'] as num).toInt(),
          ),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'creatorId': creatorId,
    'endsAt': endsAt.millisecondsSinceEpoch,
    'eligible': eligible,
    'pods': pods.values.map((p) => p.toJson()).toList(),
    'selections': selections,
    'podMemberOrder': podMemberOrder,
    'attendance': attendance,
    'finalSelections': finalSelections,
    'formedPodIds': formedPodIds,
    'finalJoins': finalJoins,
    'watches': watches,
    'deletedPodIds': deletedPodIds,
    'cancelled': cancelled,
    'cancelledAt': cancelledAt?.millisecondsSinceEpoch,
  };
}
