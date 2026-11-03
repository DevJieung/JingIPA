import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';
import 'app_repository.dart';

class DemoRepository extends AppRepository {
  final Map<String, PodRoundData> _podRounds = {};
  AppUser? _user;
  final List<LunchChannel> _channels = [];
  final Map<String, LunchRound> _rounds = {};
  final Map<String, Restaurant> _catalog = {};
  SharedPreferences? _preferences;
  Duration _offset = Duration.zero;
  Timer? _timer;
  final Map<String, int> _balances = {};
  final Map<String, Map<String, String>> _colors = {};
  final Map<String, List<String>> _favorites = {};
  final List<Map<String, dynamic>> _reports = [];
  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _joinRequests = [];
  String _joinMessage = '채널에 들어왔어요.';
  @override
  String get channelJoinMessage => _joinMessage;
  @override
  TokenWallet get wallet => TokenWallet(
    balance: _balances[user?.id] ?? 0,
    reserved: _rounds.values
        .where((r) => r.tokenStatuses[user?.id] == 'reserved')
        .fold(
          0,
          (sum, r) => sum + (r.tokenReceipts[user?.id]?['reservedCount'] ?? 1),
        ),
  );
  @override
  bool get premiumActive =>
      _rounds.values.any((r) => r.tokenStatuses[user?.id] == 'reserved');
  @override
  List<Restaurant> get favorites => (_favorites[user?.id] ?? [])
      .map((id) => _catalog[id])
      .whereType<Restaurant>()
      .toList();
  @override
  Map<String, String> colorsFor(String channelId) =>
      Map.unmodifiable(_colors['${user?.id}:$channelId'] ?? {});
  @override
  Set<String> redTargetsFor(String channelId) => colorsFor(
    channelId,
  ).entries.where((e) => e.value == 'D94B48').map((e) => e.key).toSet();

  bool _settleTokens() {
    var changed = false;
    for (final r in _rounds.values) {
      final phase = r.phaseAt(now);
      for (final uid in r.tokenStatuses.keys.toList()) {
        if (r.tokenStatuses[uid] != 'reserved') continue;
        if (phase != RoundPhase.finalized &&
            phase != RoundPhase.cancelled &&
            !r.withdrawn.contains(uid)) {
          continue;
        }
        final held = r.tokenReceipts[uid]?['reservedCount'] ?? 1;
        const charged = 0; // Retired reservations are released without debit.
        _balances[uid] = (_balances[uid] ?? 0) - charged;
        r.tokenReceipts[uid] = {
          'reservedCount': held,
          'chargedCount': charged,
          'releasedCount': held - charged,
          'settledAt': now.millisecondsSinceEpoch,
        };
        r.tokenStatuses[uid] = charged > 0 ? 'charged' : 'released';
        changed = true;
      }
    }
    return changed;
  }

  @override
  AppUser? get user => _user;
  @override
  List<LunchChannel> get channels =>
      _channels.where((c) => c.members.containsKey(user?.id)).toList();
  @override
  bool get isDemo => true;
  @override
  DateTime get now => DateTime.now().add(_offset);
  @override
  String? get connectionError => null;
  @override
  RoundView? roundFor(String channelId) {
    final channel = _channels.where((c) => c.id == channelId).firstOrNull;
    final legacy = _rounds[channel?.roundId];
    if (channel != null &&
        legacy != null &&
        !_podRounds.containsKey(legacy.id)) {
      _podRounds[legacy.id] = PodRoundData(
        id: legacy.id,
        channelId: channel.id,
        creatorId: legacy.creatorId,
        endsAt: legacy.endsAt,
        eligible: [],
        cancelled: legacy.cancelled,
        selections: Map.from(legacy.selections),
        pods: {
          for (final id in legacy.selections.values.toSet())
            id: LunchPod(
              id: id,
              name: _catalog[id]?.name ?? '함께 먹어요',
              creatorId: legacy.creatorId,
              minimum: 2,
              restaurant: _catalog[id]?.manual == true ? null : _catalog[id],
            ),
        },
      );
    }
    final pod = _podRounds[channel?.roundId];
    if (pod != null && channel != null && user != null) {
      pod.channelId ??= channel.id;
      return pod.view(user!.id, channel, now, tokens: _rounds[pod.id]);
    }
    final round = _rounds[channel?.roundId];
    return channel == null ||
            round == null ||
            user == null ||
            !channel.members.containsKey(user!.id)
        ? null
        : round.view(
            user!.id,
            channel,
            _catalog,
            now,
            redTargets: redTargetsFor(channelId),
            premiumActive: round.tokenStatuses[user!.id] == 'reserved',
            colorTargets: round.tokenColors[user!.id] ?? {},
          );
  }

  @override
  List<RoundView> roundHistoryFor(String channelId) {
    final channel = channels.where((c) => c.id == channelId).firstOrNull;
    if (channel == null || user == null) return [];
    final history = [
      for (final round in _podRounds.values)
        if (round.channelId == channelId &&
            round.id != channel.roundId &&
            !round.open(now))
          round.view(user!.id, channel, now),
    ];
    history.sort((a, b) => b.endsAt.compareTo(a.endsAt));
    return history;
  }

  @override
  Future<void> initialize() async {
    final data =
        jsonDecode(
              await rootBundle.loadString('assets/data/demo_restaurants.json'),
            )
            as List;
    for (final row in data) {
      final place = Restaurant.fromJson(Map<String, dynamic>.from(row as Map));
      _catalog[place.id] = place;
    }
    _preferences = await SharedPreferences.getInstance();
    final stored = _preferences?.getString('meokkiri.demo.v1');
    if (stored != null) {
      try {
        final j = jsonDecode(stored) as Map<String, dynamic>;
        _channels.addAll(
          (j['channels'] as List).map(
            (e) => LunchChannel.fromJson(Map<String, dynamic>.from(e as Map)),
          ),
        );
        for (final row in j['rounds'] as List) {
          final round = LunchRound.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          _rounds[round.id] = round;
        }
        for (final row in j['podRounds'] as List? ?? []) {
          final pod = PodRoundData.fromJson(Map<String, dynamic>.from(row));
          _podRounds[pod.id] = pod;
        }
        if (j['user'] != null) {
          _user = AppUser(
            j['user']['id'],
            j['user']['name'],
            emoji: j['user']['emoji'] ?? '🐘',
          );
        }
        _offset = Duration(milliseconds: j['offset'] ?? 0);
        _balances.addAll(
          (j['balances'] as Map? ?? {}).map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ),
        );
        for (final entry in (j['colors'] as Map? ?? {}).entries) {
          _colors[entry.key as String] = Map<String, String>.from(
            entry.value as Map,
          );
        }
        for (final entry in (j['favorites'] as Map? ?? {}).entries) {
          _favorites[entry.key as String] = List<String>.from(
            entry.value as List,
          );
        }
        for (final row in j['manualPlaces'] as List? ?? []) {
          final place = Restaurant.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          _catalog[place.id] = place;
        }
        _messages.addAll(
          (j['messages'] as List? ?? []).map(
            (r) => Map<String, dynamic>.from(r as Map),
          ),
        );
        _reports.addAll(
          (j['reports'] as List? ?? []).map(
            (r) => Map<String, dynamic>.from(r as Map),
          ),
        );
        _joinRequests.addAll(
          (j['joinRequests'] as List? ?? []).map(
            (r) => Map<String, dynamic>.from(r as Map),
          ),
        );
      } catch (_) {
        _channels.clear();
        _rounds.clear();
        _user = null;
      }
    }
    if (_joinRequests.isNotEmpty) {
      for (final row in _joinRequests) {
        final c = _channels.where((c) => c.id == row['channelId']).firstOrNull;
        final r = _podRounds[row['roundId']];
        if (row['status'] == 'pending' &&
            c != null &&
            r != null &&
            c.roundId == r.id &&
            r.open(now) &&
            c.members.length < 100) {
          c.members[row['requesterId']] = row['displayName'];
          c.memberEmojis = {
            ...c.memberEmojis,
            row['requesterId']: row['requesterId'] == user?.id
                ? user!.emoji
                : '🐘',
          };
        }
      }
      _joinRequests.clear();
      await _save();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_settleTokens()) {
        unawaited(_save());
      } else {
        notifyListeners();
      }
    });
  }

  void _seed() {
    final today = DateTime.now();
    _offset = DateTime(
      today.year,
      today.month,
      today.day,
      11,
      2,
    ).difference(today);
    final channel = LunchChannel(
      id: 'our-team',
      name: '우리 팀 밥방',
      ownerId: 'me',
      inviteCode: 'MEOK26',
      members: {
        'me': user!.name,
        'jiwoo': '김지우',
        'minsu': '박민수',
        'seoyeon': '이서연',
        'doyun': '최도윤',
        'haneul': '정하늘',
      },
    );
    final pod = PodRoundData(
      id: 'first-pod-lunch',
      creatorId: 'jiwoo',
      endsAt: now.add(const Duration(minutes: 30)),
      eligible: channel.members.keys.toList(),
    );
    channel.roundId = pod.id;
    _channels.add(channel);
    _podRounds[pod.id] = pod;
  }

  Future<void> _save() async {
    for (final p in _podRounds.values) {
      final shadow = _rounds.putIfAbsent(
        p.id,
        () => LunchRound(
          id: p.id,
          creatorId: p.creatorId,
          revealAt: p.endsAt,
          endsAt: p.endsAt,
        ),
      );
      shadow.revealAt = p.endsAt;
      shadow.endsAt = p.endsAt;
      shadow.manualControl = false;
      shadow.cancelled = p.cancelled;
      shadow.selections
        ..clear()
        ..addAll(p.selections);
    }
    for (final channel in _channels) {
      _rounds[channel.roundId]?.reconcileTransition(channel, now);
    }
    _settleTokens();
    notifyListeners();
    await _preferences?.setString(
      'meokkiri.demo.v1',
      jsonEncode({
        'user': user == null
            ? null
            : {'id': user!.id, 'name': user!.name, 'emoji': user!.emoji},
        'podRounds': _podRounds.values.map((r) => r.toJson()).toList(),
        'channels': _channels.map((c) => c.toJson()).toList(),
        'rounds': _rounds.values.map((r) => r.toJson()).toList(),
        'offset': _offset.inMilliseconds,
        'balances': _balances,
        'colors': _colors,
        'favorites': _favorites,
        'manualPlaces': _catalog.values
            .where((r) => r.manual)
            .map((r) => r.toJson())
            .toList(),
        'reports': _reports,
        'messages': _messages,
        'joinRequests': _joinRequests,
      }),
    );
  }

  LunchChannel _channel(String id) => channels.firstWhere((c) => c.id == id);
  LunchRound _round(String channelId) {
    final round = _rounds[_channel(channelId).roundId];
    if (round == null) throw const LunchException('먼저 라운드를 열어 주세요.');
    return round;
  }

  @override
  Future<void> enterDemo() async {
    _user = AppUser(
      'me',
      '윤수빈',
      emoji:
          _channels
              .where((c) => c.members.containsKey('me'))
              .firstOrNull
              ?.memberEmojis['me'] ??
          '🐘',
    );
    if (_channels.isEmpty) _seed();
    await _save();
  }

  @override
  Future<void> signInGoogle() async =>
      throw const LunchException('현재는 체험 버전이에요. 아래 체험 버튼으로 둘러보세요.');
  @override
  Future<void> signInApple() => signInGoogle();
  @override
  Future<void> signOut() async {
    _user = null;
    await _save();
  }

  @override
  Attendance get attendance {
    var total = 0, attended = 0;
    for (final round in _podRounds.values) {
      round.settle(now);
      if (round.attendance?.containsKey(user?.id) == true) {
        total++;
        if (round.attendance![user!.id]!) attended++;
      }
    }
    return Attendance(total: total, attended: attended);
  }

  @override
  Future<void> updateProfile(String name, String emoji) async {
    if (name.trim().isEmpty || name.trim().length > 20) {
      throw const LunchException('이름은 1~20자로 입력해 주세요.');
    }
    if (!profileEmojis.contains(emoji)) {
      throw const LunchException('목록에서 이모지를 선택해 주세요.');
    }
    _user = AppUser(user!.id, name.trim(), emoji: emoji);
    for (final c in channels) {
      c.members[user!.id] = user!.name;
      c.memberEmojis = {...c.memberEmojis, user!.id: emoji};
    }
    await _save();
  }

  @override
  Future<void> updateEmoji(String emoji) => updateProfile(user!.name, emoji);

  @override
  Future<void> startPodRound(
    String channelId,
    DateTime endsAt,
    List<String> expectedMemberIds,
  ) async {
    final c = _channel(channelId);
    if (c.members.length < 2 ||
        expectedMemberIds.toSet().length != c.members.length ||
        !expectedMemberIds.toSet().containsAll(c.members.keys)) {
      throw const LunchException('현재 구성원을 다시 확인해 주세요. 2명 이상이어야 시작할 수 있어요.');
    }
    final previous = roundFor(channelId);
    if (previous != null &&
        [
          RoundPhase.submission,
          RoundPhase.adjusting,
        ].contains(previous.phase)) {
      throw const LunchException('진행 중인 라운드가 있어요.');
    }
    _validateDeadline(endsAt);
    final availableAt = nextRoundAtFor(channelId);
    if (availableAt != null && now.isBefore(availableAt)) {
      throw RoundCooldownException(availableAt, now);
    }
    final id = 'pod-round-${DateTime.now().microsecondsSinceEpoch}';
    _podRounds[id] = PodRoundData(
      id: id,
      channelId: channelId,
      creatorId: user!.id,
      endsAt: endsAt,
      eligible: c.members.keys.toList(),
    );
    c.roundId = id;
    await _save();
  }

  void _validateDeadline(DateTime endsAt) {
    if (!endsAt.isAfter(now) ||
        endsAt.difference(now) > const Duration(hours: 24)) {
      throw const LunchException('마감은 지금부터 1분~24시간 안으로 정해 주세요.');
    }
  }

  PodRoundData _openPod(String channelId) {
    final pod = _podRounds[_channel(channelId).roundId];
    if (pod == null || !pod.open(now)) {
      throw const LunchException('모집이 마감되어 변경할 수 없어요.');
    }
    return pod;
  }

  @override
  Future<void> createPod(
    String channelId,
    String name,
    int minimum,
    String requestId, {
    String? restaurantId,
    String? restaurantText,
    TemporaryRestaurant? temporaryRestaurant,
  }) async {
    final r = _openPod(channelId);
    if (name.trim().isEmpty ||
        name.trim().length > 40 ||
        minimum < 2 ||
        minimum > 100 ||
        requestId.isEmpty) {
      throw const LunchException('팟 이름과 최소 인원을 확인해 주세요.');
    }
    final direct = restaurantText?.trim() ?? '';
    if ([
              restaurantId != null,
              restaurantText != null,
              temporaryRestaurant != null,
            ].where((v) => v).length !=
            1 ||
        direct.length > 100) {
      throw const LunchException('등록 식당을 선택하거나 직접 입력 모드를 골라 주세요.');
    }
    final restaurant = restaurantId == null ? null : _catalog[restaurantId];
    if (restaurantId != null && (restaurant == null || restaurant.manual)) {
      throw const LunchException('DB에 등록된 식당만 선택할 수 있어요.');
    }
    final id = 'pod-${user!.id}-$requestId';
    if (r.pods.containsKey(id)) return;
    if (r.pods.length >= 50) {
      throw const LunchException('팟은 최대 50개까지 만들 수 있어요.');
    }
    if (temporaryRestaurant != null) {
      await reportRestaurant(
        temporaryRestaurant.name,
        temporaryRestaurant.address,
        '음식점',
        note: '팟에서 임시 사용하며 제보한 식당',
      );
    }
    r.pods[id] = LunchPod(
      id: id,
      name: name.trim(),
      creatorId: user!.id,
      minimum: minimum,
      restaurant: restaurant,
      restaurantText: direct.isEmpty ? null : direct,
      temporaryRestaurant: temporaryRestaurant,
    );
    r.assignPod(user!.id, id);
    await _save();
  }

  @override
  Future<void> joinPod(String channelId, String podId) async {
    final r = _openPod(channelId);
    if (!r.pods.containsKey(podId)) {
      throw const LunchException('팟을 다시 확인해 주세요.');
    }
    r.assignPod(user!.id, podId);
    await _save();
  }

  @override
  Future<void> joinFinalPod(String channelId, String podId) async {
    final channel = _channel(channelId);
    final r = _podRounds[channel.roundId];
    if (r == null ||
        r.cancelled ||
        r.open(now) ||
        !channel.members.containsKey(user!.id)) {
      throw const LunchException('모집 마감 후 성사된 팟을 선택할 수 있어요.');
    }
    r.settle(now);
    if (!r.formedPodIds!.contains(podId)) {
      throw const LunchException('마감 때 성사된 팟만 선택할 수 있어요.');
    }
    if (r.finalJoins[user!.id] == podId) return;
    if (r.finalJoins.containsKey(user!.id) ||
        r.formedPodIds!.contains(r.finalSelections![user!.id])) {
      throw const LunchException('최종 선택은 미배정자만 한 번 할 수 있어요.');
    }
    r.finalJoins[user!.id] = podId;
    r.assignPod(user!.id, podId);
    await _save();
  }

  @override
  Future<void> leavePod(String channelId) async {
    _openPod(channelId).assignPod(user!.id, null);
    await _save();
  }

  @override
  Future<void> changePodDeadline(String channelId, DateTime endsAt) async {
    final r = _openPod(channelId);
    if (r.creatorId != user!.id) {
      throw const LunchException('라운드장만 마감을 바꿀 수 있어요.');
    }
    _validateDeadline(endsAt);
    r.endsAt = endsAt;
    await _save();
  }

  Future<void> finishPodDemo(
    String channelId, {
    Duration after = const Duration(seconds: 1),
  }) async {
    final r = _podRounds[_channel(channelId).roundId];
    if (r == null) return;
    _offset += r.endsAt.difference(now) + after;
    r.settle(now);
    await _save();
  }

  @override
  Future<void> updateName(String name) => updateProfile(name, user!.emoji);

  @override
  Future<void> deleteAccount() async {
    if (channels.any(
      (c) => [
        RoundPhase.submission,
        RoundPhase.adjusting,
      ].contains(roundFor(c.id)?.phase),
    )) {
      throw const LunchException('라운드 진행 중에는 계정을 삭제할 수 없어요. 라운드 종료 후 이용해 주세요.');
    }
    _channels.clear();
    _rounds.clear();
    _podRounds.clear();
    _user = null;
    _offset = Duration.zero;
    _balances.clear();
    _colors.clear();
    _favorites.clear();
    _reports.clear();
    _messages.clear();
    _joinRequests.clear();
    await _preferences?.remove('meokkiri.demo.v1');
    notifyListeners();
  }

  @override
  Future<void> leaveChannel(String channelId) =>
      _removeMembership(channelId, user!.id, leaving: true);

  @override
  Future<void> removeChannelMember(String channelId, String memberId) async {
    if (_channel(channelId).ownerId != user!.id) {
      throw const LunchException('채널장만 동료를 내보낼 수 있어요.');
    }
    if (memberId == user!.id) {
      throw const LunchException('본인은 채널 나가기를 이용해 주세요.');
    }
    await _removeMembership(channelId, memberId);
  }

  Future<void> _removeMembership(
    String channelId,
    String memberId, {
    bool leaving = false,
  }) async {
    final channel = _channel(channelId);
    if (!channel.members.containsKey(memberId)) return;
    final round = _rounds[channel.roundId];
    final pod = _podRounds[channel.roundId];
    if (pod?.open(now) == true) {
      throw const LunchException('모집 마감 후 모임 나가기·내보내기를 이용해 주세요.');
    }
    if (round?.phaseAt(now) == RoundPhase.adjusting) {
      throw const LunchException('Round2 최종 확정 후 채널 나가기·내보내기를 할 수 있어요.');
    }
    if (leaving && round?.phaseAt(now) == RoundPhase.submission) {
      throw const LunchException('라운드 진행 중에는 채널에서 나갈 수 없어요. 라운드 종료 후 이용해 주세요.');
    }
    if (round?.phaseAt(now) == RoundPhase.submission) {
      round!.withdraw(memberId, channel, now);
      for (final entry in round.tokenColors.entries) {
        if (entry.key != memberId &&
            round.tokenStatuses[entry.key] == 'reserved') {
          entry.value.remove(memberId);
          if (entry.value.isEmpty) {
            round.tokenStatuses[entry.key] = 'released';
            round.tokenReceipts[entry.key] = {
              'reservedCount': 0,
              'chargedCount': 0,
              'releasedCount': 0,
              'settledAt': now.millisecondsSinceEpoch,
            };
          } else {
            round.tokenReceipts[entry.key] = {
              'reservedCount': entry.value.length,
            };
          }
        }
      }
    }
    _settleTokens();
    for (final entry in _colors.entries.where(
      (e) => e.key.endsWith(':$channelId'),
    )) {
      entry.value.remove(memberId);
    }
    _colors.remove('$memberId:$channelId');
    channel.members.remove(memberId);
    if (channel.ownerId == memberId) {
      channel.ownerId = channel.members.keys.firstOrNull ?? '';
    }
    if (channel.members.isEmpty) _channels.remove(channel);
    await _save();
  }

  @override
  Future<void> sendCustomerMessage(String message, String requestId) async {
    if (message.trim().isEmpty || message.trim().length > 2000) {
      throw const LunchException('메시지는 1~2,000자로 입력해 주세요.');
    }
    if (!_messages.any((m) => m['id'] == '${user!.id}_$requestId')) {
      _messages.add({
        'id': '${user!.id}_$requestId',
        'ownerId': user!.id,
        'senderName': user!.name,
        'message': message.trim(),
        'createdAt': now.millisecondsSinceEpoch,
        'status': 'received',
      });
    }
    await _save();
  }

  @override
  Future<List<Map<String, dynamic>>> customerMessages({
    bool admin = false,
  }) async => _messages
      .where((m) => m['ownerId'] == user?.id)
      .toList()
      .reversed
      .toList();

  Future<void> activateDemoPremium() async =>
      throw const LunchException('현재 버전에서는 제공하지 않는 기능이에요.');

  @override
  Future<void> purchaseTokens(String bundleId) async =>
      throw const LunchException('현재 버전에서는 제공하지 않는 기능이에요.');

  @override
  Future<void> equipToken(String channelId, bool enabled) async =>
      throw const LunchException('현재 버전에서는 제공하지 않는 기능이에요.');

  @override
  Future<void> saveRedTargets(String channelId, Set<String> targets) =>
      saveColors(channelId, {for (final id in targets) id: 'D94B48'});
  @override
  Future<void> saveColors(String channelId, Map<String, String> colors) async {
    final c = _channel(channelId);
    if (roundFor(channelId)?.phase == RoundPhase.adjusting) {
      throw const LunchException('추가 시간 중에는 동료 색상을 바꿀 수 없어요.');
    }
    if (colors.entries.any(
      (e) =>
          e.key == user!.id ||
          !c.members.containsKey(e.key) ||
          !validPersonColor(e.value),
    )) {
      throw const LunchException('동료와 색상을 확인해 주세요.');
    }
    final round = _rounds[c.roundId];
    if (round?.tokenStatuses[user!.id] == 'reserved') {
      final held = round!.tokenReceipts[user!.id]?['reservedCount'] ?? 1;
      if (wallet.available + held < colors.length) {
        throw LunchException('지정한 동료 ${colors.length}명만큼 토큰이 필요해요.');
      }
      if (colors.isEmpty) {
        round.tokenStatuses.remove(user!.id);
        round.tokenColors.remove(user!.id);
        round.tokenReceipts.remove(user!.id);
      } else {
        round.tokenReceipts[user!.id] = {'reservedCount': colors.length};
      }
    }
    _colors['${user!.id}:$channelId'] = Map.from(colors);
    if (round?.tokenStatuses[user!.id] == 'reserved') {
      round!.tokenColors[user!.id] = Map.from(colors);
      round.reconcileTransition(c, now, changedUser: user!.id);
    }
    await _save();
  }

  @override
  Future<void> setFavorite(Restaurant restaurant, bool saved) async {
    final ids = _favorites.putIfAbsent(user!.id, () => []);
    if (saved && !ids.contains(restaurant.id)) {
      if (ids.length >= 200) {
        throw const LunchException('좋아하는 식당은 최대 200곳까지 저장할 수 있어요.');
      }
      ids.add(restaurant.id);
    } else if (!saved) {
      ids.remove(restaurant.id);
    }
    await _save();
  }

  @override
  Future<Restaurant> addManualRestaurant(
    String name,
    String address,
    String category, {
    bool report = false,
    bool saveToFavorites = true,
  }) async {
    if (name.trim().isEmpty ||
        name.trim().length > 80 ||
        address.trim().isEmpty ||
        address.trim().length > 200 ||
        category.trim().isEmpty ||
        category.length > 40) {
      throw const LunchException('식당 이름과 주소를 확인해 주세요.');
    }
    final duplicate = _catalog.values
        .where(
          (r) =>
              r.manual && r.name == name.trim() && r.address == address.trim(),
        )
        .firstOrNull;
    final r =
        duplicate ??
        Restaurant(
          id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
          name: name.trim(),
          address: address.trim(),
          category: category.trim(),
          manual: true,
        );
    _catalog[r.id] = r;
    if (saveToFavorites) {
      await setFavorite(r, true);
    } else {
      await _save();
    }
    if (report) await reportRestaurant(name, address, category);
    return r;
  }

  @override
  Future<void> reportRestaurant(
    String name,
    String address,
    String category, {
    String note = '',
  }) async {
    if (name.trim().isEmpty ||
        name.trim().length > 80 ||
        address.trim().isEmpty ||
        address.trim().length > 200 ||
        category.trim().isEmpty ||
        category.trim().length > 40 ||
        note.length > 500) {
      throw const LunchException('식당 이름과 주소를 확인해 주세요.');
    }
    if (!_reports.any(
      (e) =>
          e['ownerId'] == user!.id &&
          e['name'] == name.trim() &&
          e['address'] == address.trim(),
    )) {
      _reports.add({
        'id': 'report-${DateTime.now().microsecondsSinceEpoch}',
        'name': name.trim(),
        'address': address.trim(),
        'category': category.trim(),
        'status': 'pending',
        'ownerId': user!.id,
        'note': note,
      });
    }
    await _save();
  }

  @override
  Future<List<Map<String, dynamic>>> restaurantReports({
    bool admin = false,
  }) async => _reports.where((r) => r['ownerId'] == user?.id).toList();
  @override
  Future<void> resolveReport(Map<String, dynamic> data) async =>
      throw const LunchException('운영자 계정이 필요해요.');

  @override
  Future<void> refresh() => _save();
  @override
  Future<void> createChannel(String name) async {
    if (name.trim().isEmpty || name.trim().length > 30) {
      throw const LunchException('채널 이름은 1~30자로 입력해 주세요.');
    }
    _channels.add(
      LunchChannel(
        id: 'channel-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(),
        ownerId: user!.id,
        members: {user!.id: user!.name},
        inviteCode: List.generate(
          6,
          (_) =>
              'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[Random.secure().nextInt(32)],
        ).join(),
      ),
    );
    await _save();
  }

  @override
  Future<void> joinChannel(String code) async {
    final channel = _channels
        .where((c) => c.inviteCode == code.trim().toUpperCase())
        .firstOrNull;
    if (channel == null) throw const LunchException('초대 코드를 다시 확인해 주세요.');
    _joinMessage = '채널에 들어왔어요.';
    if (channel.members.containsKey(user!.id)) return;
    if (channel.members.length >= 100) {
      throw const LunchException('채널은 최대 100명까지 함께할 수 있어요.');
    }
    _joinRequests.removeWhere((r) => r['id'] == '${channel.id}_${user!.id}');
    channel.members[user!.id] = user!.name;
    channel.memberEmojis = {...channel.memberEmojis, user!.id: user!.emoji};
    await _save();
  }

  @override
  Future<void> saveDefaults(
    String channelId,
    int revealMinute,
    int additionalMinutes,
  ) async {
    final c = _channel(channelId);
    if (c.ownerId != user!.id) {
      throw const LunchException('채널을 만든 사람만 기본 시간을 변경할 수 있어요.');
    }
    c.revealMinute = revealMinute;
    c.additionalMinutes = additionalMinutes;
    await _save();
  }

  @override
  Future<void> startRound(
    String channelId,
    DateTime revealAt,
    int additionalMinutes, {
    List<String>? expectedMemberIds,
  }) async {
    final c = _channel(channelId);
    if (c.members.length < 2) {
      throw const LunchException('채널에 2명 이상 있어야 라운드를 열 수 있어요. 동료를 초대해 주세요.');
    }
    if (expectedMemberIds != null &&
        (expectedMemberIds.length != c.members.length ||
            !expectedMemberIds.toSet().containsAll(c.members.keys))) {
      throw const LunchException('채널 구성원이 바뀌었어요. 명단을 다시 확인하고 라운드를 열어 주세요.');
    }
    final existing = _rounds[c.roundId];
    if (existing != null &&
        [
          RoundPhase.submission,
          RoundPhase.adjusting,
        ].contains(existing.phaseAt(now))) {
      throw const LunchException('이미 진행 중인 라운드가 있어요.');
    }
    if (!revealAt.isAfter(now) ||
        revealAt.difference(now) > const Duration(hours: 24) ||
        additionalMinutes < 1 ||
        additionalMinutes > 120) {
      throw const LunchException('공개 시각과 추가 시간을 확인해 주세요.');
    }
    final id = 'round-${DateTime.now().microsecondsSinceEpoch}';
    _rounds[id] = LunchRound(
      id: id,
      creatorId: user!.id,
      cutoffControl: true,
      eligibleMemberIds: c.members.keys.toList(),
      revealAt: revealAt,
      endsAt: revealAt.add(Duration(minutes: additionalMinutes)),
    );
    c.roundId = id;
    await _save();
  }

  @override
  Future<List<Restaurant>> search(String query, {SearchLocation? near}) async =>
      _catalog.values
          .where((r) => !r.manual)
          .where(
            (r) => '${r.name} ${r.category} ${r.address}'
                .toLowerCase()
                .contains(query.trim().toLowerCase()),
          )
          .toList();
  @override
  Future<void> choose(String channelId, String restaurantId) async {
    final changed = _round(channelId).selections[user!.id] != restaurantId;
    _round(
      channelId,
    ).choose(user!.id, restaurantId, _channel(channelId), _catalog, now);
    _round(channelId).reconcileTransition(
      _channel(channelId),
      now,
      changedUser: changed ? user!.id : null,
    );
    await _save();
  }

  @override
  Future<void> withdraw(String channelId) async {
    _round(channelId).withdraw(user!.id, _channel(channelId), now);
    await _save();
  }

  @override
  Future<void> joinFinalParty(String channelId, String restaurantId) async {
    _settleTokens();
    _round(
      channelId,
    ).joinFinalParty(user!.id, restaurantId, _channel(channelId), now);
    await _save();
  }

  @override
  Future<void> cancelRound(String channelId) async {
    final pod = _podRounds[_channel(channelId).roundId];
    if (pod != null) {
      if (!pod.open(now) || pod.creatorId != user!.id) {
        throw const LunchException('진행 중인 라운드의 라운드장만 취소할 수 있어요.');
      }
      pod.cancelled = true;
      pod.cancelledAt = now;
      await _save();
      return;
    }
    _round(channelId).cancel(user!.id, _channel(channelId), now);
    await _save();
  }

  @override
  Future<void> setRoundCutoffs(
    String channelId,
    RoundPhase expectedPhase,
    DateTime revealAt,
    DateTime endsAt,
  ) async {
    final round = _round(channelId);
    if (round.creatorId != user!.id) {
      throw const LunchException('현재 라운드의 라운드장만 마감 시간을 정할 수 있어요.');
    }
    if (round.phaseAt(now) != expectedPhase ||
        ![
          RoundPhase.submission,
          RoundPhase.adjusting,
        ].contains(expectedPhase)) {
      throw const LunchException('라운드 단계가 변경되었어요. 현재 화면에서 다시 설정해 주세요.');
    }
    final first = expectedPhase == RoundPhase.submission;
    final duration = endsAt.difference(first ? revealAt : now);
    if ((first &&
            (!revealAt.isAfter(now) ||
                revealAt.difference(now) > const Duration(hours: 24))) ||
        duration < const Duration(minutes: 1) ||
        duration > const Duration(minutes: 120)) {
      throw const LunchException('마감 시간을 확인해 주세요. Round2는 1~120분 사이로 정해 주세요.');
    }
    if (first) round.revealAt = revealAt;
    round.endsAt = endsAt;
    round.manualControl = false;
    round.cutoffControl = true;
    round.eligibleMemberIds ??= _channel(channelId).members.keys.toList();
    round.pendingTransition = null;
    await _save();
  }

  @override
  Future<void> advanceRound(String channelId, RoundPhase expectedPhase) async {
    final round = _round(channelId);
    if (round.cutoffControl) {
      throw const LunchException('설정한 마감 시각에 자동으로 진행돼요. 마감 시간을 확인해 주세요.');
    }
    if (round.creatorId != user!.id) {
      throw const LunchException('라운드를 연 사람만 공개하거나 확정할 수 있어요.');
    }
    if (round.phaseAt(now) != expectedPhase ||
        ![
          RoundPhase.submission,
          RoundPhase.adjusting,
        ].contains(expectedPhase)) {
      throw const LunchException('라운드 단계가 변경되었어요. 다시 확인해 주세요.');
    }
    round.manualControl = true;
    round.manualPhase = expectedPhase;
    round.pendingTransition ??= {
      'id': 'approval-${DateTime.now().microsecondsSinceEpoch}',
      'phase': expectedPhase.name,
      'requiredIds': round.approvalMembers(_channel(channelId)).toList(),
      'approvedIds':
          round.approvalMembers(_channel(channelId)).contains(user!.id)
          ? [user!.id]
          : <String>[],
    };
    round.reconcileTransition(_channel(channelId), now);
    await _save();
  }

  @override
  Future<void> approveRoundTransition(
    String channelId,
    String transitionId,
    RoundPhase phase,
  ) async {
    final round = _round(channelId);
    if (round.cutoffControl) {
      throw const LunchException('설정한 마감 시각에 자동으로 진행돼요. 동의는 필요하지 않아요.');
    }
    final pending = round.pendingTransition;
    if (pending == null ||
        pending['id'] != transitionId ||
        pending['phase'] != phase.name ||
        round.phaseAt(now) != phase ||
        !round.approvalMembers(_channel(channelId)).contains(user!.id)) {
      throw const LunchException('동의 요청이 변경되었어요. 현재 라운드를 확인해 주세요.');
    }
    pending['approvedIds'] = {
      ...List<String>.from(pending['approvedIds']),
      user!.id,
    }.toList();
    round.reconcileTransition(_channel(channelId), now);
    await _save();
  }

  Future<void> advance(String channelId, {required bool finalize}) async {
    final r = _round(channelId);
    final target = (finalize ? r.endsAt : r.revealAt).add(
      const Duration(seconds: 1),
    );
    if (target.isAfter(now)) _offset += target.difference(now);
    r.synchronize(now);
    await _save();
  }

  Future<void> simulateMove(String channelId) async {
    final c = _channel(channelId), r = _round(channelId);
    r.synchronize(now);
    if (r.phaseAt(now) != RoundPhase.adjusting || r.optionIds.length < 2) {
      throw const LunchException('식당 공개 후 선택 변경을 체험할 수 있어요.');
    }
    final actor = c.members.keys.firstWhere((id) => id != user!.id);
    final current = r.selections[actor];
    final next = r.optionIds.firstWhere((id) => id != current);
    r.choose(actor, next, c, _catalog, now);
    await _save();
  }

  Future<void> switchPerson(String uid) async {
    final name = _channels
        .expand((c) => c.members.entries)
        .firstWhere((e) => e.key == uid)
        .value;
    _user = AppUser(
      uid,
      name,
      emoji:
          _channels
              .where((c) => c.members.containsKey(uid))
              .firstOrNull
              ?.memberEmojis[uid] ??
          '🐘',
    );
    await _save();
  }

  Future<void> loadRedExample() async {
    _channels.clear();
    _rounds.clear();
    _podRounds.clear();
    _colors.clear();
    _balances.clear();
    final today = DateTime.now();
    _offset = DateTime(
      today.year,
      today.month,
      today.day,
      11,
      20,
    ).difference(today);
    _user = const AppUser('e', 'E (나)');
    _balances['e'] = 1;
    final c = LunchChannel(
      id: 'red-example',
      name: 'A·B Red 예시',
      ownerId: 'a',
      inviteCode: 'REDEMO',
      members: {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E (나)'},
    );
    final r = LunchRound(
      id: 'red-example-round',
      creatorId: 'a',
      revealAt: now.subtract(const Duration(seconds: 1)),
      endsAt: now.add(const Duration(minutes: 10)),
      selections: {
        'a': 'demo-1',
        'b': 'demo-2',
        'c': 'demo-3',
        'd': 'demo-3',
        'e': 'demo-2',
      },
    );
    r.synchronize(now);
    c.roundId = r.id;
    _channels.add(c);
    _rounds[r.id] = r;
    _colors['e:red-example'] = {'a': 'D94B48', 'b': 'D94B48'};
    r.tokenStatuses['e'] = 'reserved';
    r.tokenColors['e'] = Map.from(_colors['e:red-example']!);
    await _save();
  }

  Future<void> reset() async {
    _channels.clear();
    _rounds.clear();
    _podRounds.clear();
    _offset = Duration.zero;
    _balances.clear();
    _colors.clear();
    _favorites.clear();
    _reports.clear();
    _messages.clear();
    _user = const AppUser('me', '윤수빈');
    _seed();
    await _save();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
