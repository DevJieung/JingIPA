import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../data/location_access.dart';
import '../domain/models.dart';
import 'theme.dart';
import 'feature_screens.dart';
import 'profile_editor.dart';
import 'round_cooldown_dialog.dart';
import 'load_notice.dart';
import 'pod_farm.dart';
import 'pod_storefront.dart';

String podTime(DateTime t) =>
    '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class AttendanceCard extends StatelessWidget {
  const AttendanceCard({required this.attendance, this.repository, super.key});
  final Attendance attendance;
  final AppRepository? repository;
  @override
  Widget build(BuildContext context) {
    if (repository?.attendanceStatus
        case LoadStatus.idle || LoadStatus.loading) {
      return const Surface(child: Text('참석률을 불러오고 있어요.'));
    }
    if (repository?.attendanceStatus == LoadStatus.failed) {
      return Surface(
        child: Column(
          children: [
            const Text('참석률을 확인하지 못했어요.'),
            TextButton(
              onPressed: () =>
                  unawaited(repository!.loadAttendance(force: true)),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    return Surface(
      color: sageSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined, color: orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  attendance.badge,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                attendance.rate == null ? '—' : '${attendance.rate}%',
                key: const Key('attendance-rate'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '참석 ${attendance.attended}회 / 마감된 라운드 ${attendance.total}회',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            '구성원으로 시작한 라운드 중 마감 때 최소 인원을 채운 팟에 속한 비율이에요. 실제 식사 확인 기록은 아니에요. 5회 이상·참석률 90% 이상이면 프로참석러!',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }
}

class PodLobby extends StatefulWidget {
  const PodLobby({
    required this.repository,
    required this.channel,
    required this.onChangeChannel,
    required this.onHelp,
    this.locationAccess = const LocationAccess(),
    this.initialRestaurant,
    super.key,
  });
  final AppRepository repository;
  final LunchChannel? channel;
  final VoidCallback onChangeChannel, onHelp;
  final LocationAccess locationAccess;
  final Restaurant? initialRestaurant;
  @override
  State<PodLobby> createState() => _PodLobbyState();
}

class _PodLobbyState extends State<PodLobby> {
  AppRepository get repo => widget.repository;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialRestaurant != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _create());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on RoundCooldownException catch (e) {
      if (mounted) await _cooldown(e.availableAt);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cooldown(DateTime availableAt) => showDialog<void>(
    context: context,
    builder: (_) =>
        RoundCooldownDialog(availableAt: availableAt, now: () => repo.now),
  );

  Future<void> _create() async {
    final c = widget.channel;
    if (c == null) return;
    await featureSheet<void>(
      context,
      PodCreateForm(
        repository: repo,
        channel: c,
        locationAccess: widget.locationAccess,
        initialRestaurant: widget.initialRestaurant,
      ),
    );
  }

  Future<void> _deadline({bool edit = false}) async {
    final c = widget.channel!;
    if (!edit) {
      final availableAt = repo.nextRoundAtFor(c.id);
      if (availableAt != null && repo.now.isBefore(availableAt)) {
        await _cooldown(availableAt);
        return;
      }
    }
    final minutes = TextEditingController(text: '30');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(edit ? '모집 마감 변경' : '새 라운드 열기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('한 번의 마감까지 자유롭게 팟을 만들고 참여해요.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('pod-deadline-minutes'),
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '지금부터 몇 분 뒤 마감할까요?',
                helperText: '1~1440분 (24시간)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final n = int.tryParse(minutes.text);
              if (n != null && n >= 1 && n <= 1440) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('다음'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final endsAt = repo.now.add(Duration(minutes: value));
    if (edit) {
      await _run(() => repo.changePodDeadline(c.id, endsAt));
      return;
    }
    final expected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: repo,
        builder: (context, _) {
          final current = repo.channels.where((x) => x.id == c.id).firstOrNull;
          final people = current?.members ?? <String, String>{};
          return AlertDialog(
            key: const Key('round-members-confirmation'),
            scrollable: true,
            title: const Text('내가 라운드장이 되어 시작할까요?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '모집 마감 ${podTime(endsAt)}',
                  style: const TextStyle(
                    color: orange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text('현재 구성원 ${people.length}명'),
                for (final p in people.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${p.value}${p.key == repo.user!.id ? ' (나)' : ''}',
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  '빈 대기실로 시작해요. 새 구성원은 초대 링크·코드로 바로 입장하며 마감 전에는 모임 나가기·계정 삭제가 제한돼요.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              TextButton(
                key: const Key('confirm-start-round'),
                onPressed: people.length < 2
                    ? null
                    : () => Navigator.pop(ctx, people.keys.toList()),
                child: const Text('라운드장으로 시작'),
              ),
            ],
          );
        },
      ),
    );
    if (expected != null && mounted) {
      await _run(() => repo.startPodRound(c.id, endsAt, expected));
    }
  }

  Widget _newRound() => FilledButton.icon(
    key: const Key('new-pod-round'),
    style: FilledButton.styleFrom(backgroundColor: orange),
    onPressed: _busy || repo.isGuest || widget.channel!.members.length < 2
        ? null
        : () => _deadline(),
    icon: const Icon(Icons.add_rounded),
    label: const Text('새 라운드 열기 · 내가 라운드장'),
  );
  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    final r = c == null ? null : repo.roundFor(c.id);
    if (c != null && c.roundId != null && r?.id != c.roundId) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PageHeading(title: '식당 정하기', onHelp: widget.onHelp),
          const SizedBox(height: 12),
          Surface(
            child: Row(
              children: [
                Expanded(child: Text('선택한 모임: ${c.name}')),
                TextButton(
                  onPressed: widget.onChangeChannel,
                  child: const Text('모임 변경'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LoadNotice(
            key: const Key('round-loading'),
            message: repo.roundErrorFor(c.id) ?? '현재 팟을 불러오고 있어요.',
            failed: repo.roundStatusFor(c.id) == LoadStatus.failed,
            onRetry: () => unawaited(repo.selectChannel(c.id)),
          ),
        ],
      );
    }
    final open = r != null && r.phase == RoundPhase.submission;
    final finalized = r != null && r.phase == RoundPhase.finalized;
    final mine = r?.pods.where((p) => p.id == r.myPodId).firstOrNull;
    final history = <RoundView>[
      if (r != null && r.phase == RoundPhase.cancelled) r,
      if (c != null) ...repo.roundHistoryFor(c.id),
    ];
    final footer = <Widget>[
      if (c != null) ...[
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 16),
        _history(history),
      ],
    ];
    final main = <Widget>[
      PageHeading(title: '식당 정하기', onHelp: widget.onHelp),
      if (c != null && repo.roundErrorFor(c.id) != null)
        TextButton(
          onPressed: () => unawaited(repo.selectChannel(c.id)),
          child: Text('${repo.roundErrorFor(c.id)} 다시 시도'),
        ),
      const SizedBox(height: 12),
      if (c == null)
        Surface(
          child: Column(
            children: [
              const ElephantArt(size: 120, scene: ElephantScene.together),
              const Text('함께 먹을 모임을 먼저 골라주세요.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.onChangeChannel,
                child: const Text('모임 선택'),
              ),
            ],
          ),
        )
      else ...[
        Surface(
          key: const Key('selected-channel'),
          color: sageSurface,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '선택한 모임: ${c.name}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('change-channel'),
                onPressed: widget.onChangeChannel,
                child: const Text('모임 변경'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          open
              ? '새로운 팟 · ${r.pods.length}개'
              : finalized
              ? '최종결과'
              : '새로운 팟',
          key: const Key('new-pods-heading'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (!open) ...[
          if (finalized) ...[
            Surface(
              key: const Key('final-pods-section'),
              color: sageSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Tag('모집 마감', color: lime),
                  const SizedBox(height: 8),
                  Text('마감 ${podTime(r.endsAt)}'),
                  const SizedBox(height: 8),
                  const Text(
                    '새 라운드를 열기 전까지 최종결과를 여기서 확인할 수 있어요.',
                    style: TextStyle(fontSize: 12, color: forest),
                  ),
                  const SizedBox(height: 12),
                  _myStatus(r, mine),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (r.pods.isEmpty)
              const Surface(child: Text('만들어진 팟이 없어요.'))
            else
              _podCards(r, false),
            const SizedBox(height: 20),
          ],
          Surface(
            key: const Key('new-pods-section'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: ElephantArt(size: 100, scene: ElephantScene.together),
                ),
                const Text('새 라운드를 열고 밥팟을 모아보세요.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                _newRound(),
                if (repo.isGuest)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('라운드를 열려면 내 프로필에서 계정을 연결해 주세요.'),
                  ),
                if (c.members.length < 2)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('동료를 초대해 2명 이상 모이면 시작할 수 있어요.'),
                  ),
              ],
            ),
          ),
        ] else ...[
          Surface(
            key: const Key('new-pods-section'),
            color: recruitingSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Tag('팟 모집 중', color: recruitingSurface),
                    Text(
                      '마감 ${podTime(r.endsAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (open)
                      Text(
                        _remaining(r.endsAt),
                        key: const Key('pod-countdown'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '마감 전까지 팟을 만들거나 옮길 수 있어요. 최소 인원을 채우면 함께 출발!',
                  style: TextStyle(fontSize: 12, color: forest),
                ),
                if (open && r.creatorId == repo.user!.id)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _deadline(edit: true),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('마감 변경'),
                  ),
                const SizedBox(height: 12),
                _myStatus(r, mine),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (r.pods.isEmpty)
            const Surface(
              child: Column(
                children: [
                  ElephantArt(size: 100, scene: ElephantScene.together),
                  SizedBox(height: 8),
                  Text(
                    '아직 팟이 없어요',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '+ 버튼으로 첫 팟을 만들어 보세요.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (r.pods.isNotEmpty) _podCards(r, open),
          if (open) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('create-pod'),
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add_rounded, size: 28),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('팟 만들기'),
              ),
            ),
          ],
        ],
      ],
    ];
    final sidebar = <Widget>[
      if (c != null)
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '대기실',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Tag(
                    '${open || finalized ? r.waitingCount : c.members.length}명 대기',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                finalized
                    ? '함께 갈 팟을 기다리는 동물 친구들이에요.'
                    : '동물 친구들과 쉬다가 마음에 드는 밥집으로 들어가요.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              if (open && mine != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('leave-pod'),
                  onPressed: _busy
                      ? null
                      : () => _run(() => repo.leavePod(c.id)),
                  child: const Text('대기실로 복귀'),
                ),
              ],
              const SizedBox(height: 14),
              WaitingFarm(
                key: const Key('waiting-farm'),
                members: open || finalized
                    ? r.waitingMembers
                    : [
                        for (final e in c.members.entries)
                          AppUser(
                            e.key,
                            '',
                            emoji: c.memberEmojis[e.key] ?? '🐘',
                          ),
                      ],
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      AttendanceCard(attendance: repo.attendance, repository: repo),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 900) {
          return ListView(
            key: const PageStorageKey('pod-lobby'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              ...main,
              const SizedBox(height: 20),
              ...sidebar,
              ...footer,
            ],
          );
        }
        return ListView(
          key: const PageStorageKey('pod-lobby-wide'),
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: main,
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 280,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 56),
                    child: Column(children: sidebar),
                  ),
                ),
              ],
            ),
            ...footer,
          ],
        );
      },
    );
  }

  String _remaining(DateTime ends) {
    final seconds = ends.difference(repo.now).inSeconds.clamp(0, 86400);
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds % 3600 ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _history(List<RoundView> rounds) => Surface(
    key: const Key('past-pods-section'),
    color: historySurface,
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      key: PageStorageKey(
        'past-pods-${widget.channel!.id}-${widget.channel!.roundId ?? 'none'}',
      ),
      onExpansionChanged: (expanded) {
        if (expanded) unawaited(repo.loadHistory(widget.channel!.id));
      },
      leading: const Icon(Icons.history_rounded, color: historyInk),
      title: const Text(
        '과거 이력',
        style: TextStyle(
          color: historyInk,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        repo.historyStatusFor(widget.channel!.id) == LoadStatus.ready
            ? '${rounds.length}개 라운드'
            : '펼쳐서 이전 라운드 확인',
        style: const TextStyle(color: historyInk, fontSize: 11),
      ),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        if (repo.historyStatusFor(widget.channel!.id) == LoadStatus.loading)
          const Text('과거 이력을 불러오고 있어요.', style: TextStyle(color: historyInk)),
        if (repo.historyStatusFor(widget.channel!.id) == LoadStatus.failed) ...[
          const Text('과거 이력을 불러오지 못했어요.', style: TextStyle(color: historyInk)),
          TextButton(
            onPressed: () =>
                unawaited(repo.loadHistory(widget.channel!.id, force: true)),
            child: const Text('다시 시도'),
          ),
        ],
        if (repo.historyStatusFor(widget.channel!.id) == LoadStatus.ready &&
            rounds.isEmpty)
          const Text('이전 라운드가 없어요.', style: TextStyle(color: historyInk)),
        for (final r in rounds)
          ExpansionTile(
            key: PageStorageKey('past-round-${r.id}'),
            title: Text(
              '${podTime(r.endsAt)} · ${r.phase == RoundPhase.cancelled ? '모집 취소' : '모집 마감'}',
              style: const TextStyle(color: historyInk, fontSize: 13),
            ),
            subtitle: Text(
              '${r.pods.length}개 팟',
              style: const TextStyle(color: historyInk, fontSize: 11),
            ),
            children: [
              if (r.pods.isEmpty)
                const Text('만들어진 팟이 없어요.', style: TextStyle(color: historyInk))
              else
                _podCards(r, false, archived: true),
              if (r.pods.where((p) => p.id == r.myPodId).firstOrNull
                  case final mine?)
                _myResult(r, mine, archived: true),
              const SizedBox(height: 16),
            ],
          ),
      ],
    ),
  );

  Widget _myResult(
    RoundView r,
    LunchPod mine, {
    bool archived = false,
  }) => Padding(
    key: Key('my-pod-result-${r.id}'),
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          r.phase == RoundPhase.cancelled
              ? '${mine.name} · 모집 취소'
              : mine.formed
              ? '${mine.name} · 팟 성사'
              : '${mine.name} · 최소 인원 미달',
          style: TextStyle(
            color: archived ? historyInk : forest,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (r.phase == RoundPhase.finalized && mine.formed) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final person in [repo.user!, ...r.companions])
                Chip(
                  backgroundColor: archived ? historyCardSurface : sageSurface,
                  avatar: Text(
                    person.emoji,
                    style: const TextStyle(fontFamily: 'NotoColorEmoji'),
                  ),
                  label: Text(person.name),
                  labelStyle: TextStyle(color: archived ? historyInk : forest),
                ),
            ],
          ),
        ],
      ],
    ),
  );

  String _podRestaurant(LunchPod p) => p.temporaryRestaurant != null
      ? '🍽️ ${p.temporaryRestaurant!.name} [임시]'
      : p.restaurant == null
      ? '🍽️ ${p.restaurantText ?? '식당 미정'}'
      : '${p.restaurant!.emoji} ${p.restaurant!.name}';

  String _podStatus(LunchPod p, RoundView r, bool open) =>
      '최소 ${p.minimum}명 · ${r.phase == RoundPhase.cancelled
          ? '모집 취소'
          : p.formed
          ? open
                ? '출발 준비 완료'
                : '팟 성사'
          : open
          ? '${p.minimum - p.count}명 더 필요'
          : '미성사'}';

  List<TextStyle> _podStyles(bool archived) => [
    TextStyle(
      color: archived ? historyInk : ink,
      fontWeight: FontWeight.w800,
      fontSize: archived ? 16 : 18,
    ),
    TextStyle(color: archived ? historyInk : ink, fontWeight: FontWeight.w600),
    TextStyle(fontSize: 11, color: archived ? historyInk : muted),
    TextStyle(fontSize: 12, color: archived ? historyInk : muted),
    TextStyle(
      color: archived ? historyInk : ink,
      fontSize: archived ? 16 : 20,
      fontWeight: FontWeight.w900,
    ),
  ];

  Size _podTextSize(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: width);
    final size = painter.size;
    painter.dispose();
    return size;
  }

  Widget _podCards(
    RoundView r,
    bool open, {
    bool archived = false,
  }) => LayoutBuilder(
    builder: (context, box) {
      final columns = ResponsiveCards.columnsFor(
        context,
        box.maxWidth,
        minWidth: 235,
      );
      final roomWidth = (box.maxWidth - (columns - 1) * 16) / columns - 36;
      List<double>? heights;
      if (columns > 1) {
        // Measure each content row at the actual card width. Shared heights
        // keep every row aligned without truncating long names or addresses.
        final width = (box.maxWidth - (columns - 1) * 16) / columns - 36;
        final styles = _podStyles(archived);
        final badge = _podTextSize(
          '내 팟',
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          double.infinity,
        );
        heights = List.filled(5, 0);
        for (final p in r.pods) {
          final texts = [
            p.name,
            _podRestaurant(p),
            p.temporaryRestaurant?.address ?? p.restaurant?.address ?? '',
            _podStatus(p, r, open),
            '${p.count}명 모임',
          ];
          for (var i = 0; i < texts.length; i++) {
            final height = texts[i].isEmpty
                ? 0.0
                : _podTextSize(
                    texts[i],
                    styles[i],
                    i == 0 ? width - badge.width - 48 : width,
                  ).height;
            heights[i] = math.max(
              heights[i],
              i == 0 ? math.max(height, badge.height + 10) : height,
            );
          }
        }
      }
      return ResponsiveCards(
        minWidth: 235,
        children: [
          for (final p in r.pods)
            _pod(
              p,
              r,
              open,
              roomWidth: roomWidth,
              archived: archived,
              heights: heights,
            ),
        ],
      );
    },
  );

  Widget _pod(
    LunchPod p,
    RoundView r,
    bool open, {
    required double roomWidth,
    bool archived = false,
    List<double>? heights,
  }) {
    final selected = p.id == r.myPodId;
    final styles = _podStyles(archived);
    Widget row(int index, Widget child) => SizedBox(
      height: heights?[index],
      child: Align(alignment: Alignment.topLeft, heightFactor: 1, child: child),
    );
    return Container(
      key: Key('pod-card-${p.id}'),
      decoration: BoxDecoration(
        // Reserve the same border space when moving between pods.
        border: Border.all(
          color: selected && !archived ? forest.withValues(alpha: .55) : line,
          width: 2,
        ),
        color: archived ? historyCardSurface : Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PodAwning(archived: archived),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: archived ? historySurface : shopSignSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: row(
                      0,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              style: styles[0].copyWith(
                                color: archived ? historyInk : forest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Visibility(
                            visible: selected,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: Tag(
                              '내 팟',
                              color: archived
                                  ? historyCardSurface
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  row(
                    1,
                    p.temporaryRestaurant == null
                        ? Text(_podRestaurant(p), style: styles[1])
                        : Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '🍽️ ${p.temporaryRestaurant!.name} ',
                                ),
                                TextSpan(
                                  text: '[임시]',
                                  style: TextStyle(
                                    color: archived ? historyInk : orange,
                                    backgroundColor: archived
                                        ? historySurface
                                        : peachSurface,
                                  ),
                                ),
                              ],
                            ),
                            style: styles[1],
                          ),
                  ),
                  row(
                    2,
                    p.restaurant == null && p.temporaryRestaurant == null
                        ? const SizedBox.shrink()
                        : Text(
                            p.temporaryRestaurant?.address ??
                                p.restaurant!.address,
                            style: styles[2],
                          ),
                  ),
                  const SizedBox(height: 12),
                  row(
                    3,
                    Text(
                      _podStatus(p, r, open),
                      key: Key('pod-minimum-${p.id}'),
                      style: styles[3].copyWith(
                        color: archived
                            ? historyInk
                            : p.formed
                            ? forest
                            : muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  row(
                    4,
                    Text(
                      '${p.count}명 모임',
                      key: Key('pod-count-${p.id}'),
                      style: styles[4],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: PodSeatingRoom.heightForWidth(roomWidth),
                    child: PodSeatingRoom(
                      key: Key('pod-members-${p.id}'),
                      minimum: p.minimum,
                      count: p.count,
                      selected: selected,
                      emoji: repo.user!.emoji,
                      occupantEmojis: p.occupantEmojis,
                      ownSeatIndex: p.ownSeatIndex,
                      archived: archived,
                    ),
                  ),
                  if (open) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      key: Key('join-${p.id}'),
                      onPressed: selected || _busy
                          ? null
                          : () => _run(
                              () => repo.joinPod(widget.channel!.id, p.id),
                            ),
                      child: Text(selected ? '✓ 내 팟' : '이 팟에 참여'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The round's own status surface carries "현재 나의 상태": while recruiting
  /// it shows the pod I am in; after the cutoff it lists the companions of my
  /// formed pod, or offers the formed pods as a one-time last chance.
  Widget _myStatus(RoundView r, LunchPod? mine) {
    final open = r.phase == RoundPhase.submission;
    final formedPods = [
      for (final p in r.pods)
        if (p.formed) p,
    ];
    final status = open
        ? mine?.name ?? '대기실에서 기다리는 중'
        : mine == null
        ? '이번 라운드에 참여하지 않았어요'
        : '${mine.name} · ${mine.formed ? '팟 성사' : '최소 인원 미달'}';
    const heading = TextStyle(fontWeight: FontWeight.w800, color: forest);
    return Container(
      key: const Key('my-status-box'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EmojiAvatar(
                repo.user!.emoji,
                key: const Key('lobby-profile-emoji'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '현재 나의 상태',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      status,
                      key: const Key('my-status-text'),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!open && mine != null && mine.formed) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              '같이 먹을 동료 · ${r.companions.length}명',
              key: Key('my-companions-${r.id}'),
              style: heading,
            ),
            const SizedBox(height: 8),
            if (r.companions.isEmpty)
              const Text(
                '같은 팟의 동료가 없어요.',
                style: TextStyle(color: muted, fontSize: 12),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Plain pills: Material chips announce as checkboxes.
                  for (final person in r.companions)
                    Container(
                      key: Key('companion-${person.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: sageSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${person.emoji} ',
                              style: const TextStyle(
                                fontFamily: 'NotoColorEmoji',
                              ),
                            ),
                            TextSpan(text: person.name),
                          ],
                        ),
                        style: const TextStyle(
                          color: forest,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            if (r.finalPodJoined)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '마지막 기회로 이 팟에 합류했어요.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
          ] else if (r.canJoinFinalPod) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text('마지막 기회! 성사된 팟에 합류해요', style: heading),
            const SizedBox(height: 4),
            const Text(
              '눌러서 함께 갈 팟을 정해요. 한 번만 선택할 수 있어요.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (final p in formedPods)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _finalChoice(p),
              ),
          ] else if (!open && formedPods.isEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '성사된 팟이 없어 최종 선택을 할 수 없어요.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _finalChoice(LunchPod p) => OutlinedButton(
    key: Key('final-join-${p.id}'),
    style: OutlinedButton.styleFrom(
      backgroundColor: sageSurface,
      foregroundColor: forest,
      side: const BorderSide(color: line),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      minimumSize: const Size.fromHeight(actionHeight),
      alignment: Alignment.centerLeft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    onPressed: _busy ? null : () => _finalJoin(p),
    child: Row(
      children: [
        Expanded(
          child: Text(
            p.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${p.count}명',
          key: Key('final-join-count-${p.id}'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );

  Future<void> _finalJoin(LunchPod pod) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('final-join-confirm'),
        title: const Text('정말 이 팟으로 참여하시겠습니까?'),
        content: Text(
          '${pod.name} · 현재 ${pod.count}명\n한 번 참여하면 다른 팟으로 바꾸거나 대기실로 돌아갈 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니요'),
          ),
          FilledButton(
            key: const Key('final-join-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('예'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => repo.joinFinalPod(widget.channel!.id, pod.id));
    }
  }
}

class PodMemberBar extends StatelessWidget {
  const PodMemberBar({
    required this.minimum,
    required this.count,
    this.archived = false,
    super.key,
  });
  final int minimum, count;
  final bool archived;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '모집 인원: 최소 $minimum명, 현재 $count명',
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < (count > minimum ? count : minimum); i++)
          Container(
            key: ValueKey('member-slot-$i'),
            width: 18,
            height: 6,
            decoration: BoxDecoration(
              color: i >= count
                  ? peachSurface
                  : i < minimum
                  ? archived
                        ? orange.withValues(alpha: .6)
                        : orange
                  : archived
                  ? historyInk
                  : forest,
              border: i >= count
                  ? Border.all(color: orange.withValues(alpha: .45))
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    ),
  );
}

enum PodRestaurantMode { catalog, direct }

class PodCreateForm extends StatefulWidget {
  const PodCreateForm({
    required this.repository,
    required this.channel,
    this.initialRestaurant,
    this.locationAccess = const LocationAccess(),
    super.key,
  });
  final AppRepository repository;
  final LunchChannel channel;
  final Restaurant? initialRestaurant;
  final LocationAccess locationAccess;
  @override
  State<PodCreateForm> createState() => _PodCreateFormState();
}

class _PodCreateFormState extends State<PodCreateForm> {
  final _name = TextEditingController();
  final _restaurantText = TextEditingController();
  PodRestaurantMode _mode = PodRestaurantMode.catalog;
  final _form = GlobalKey<FormState>();
  late Restaurant? _restaurant = widget.initialRestaurant;
  TemporaryRestaurant? _temporary;
  final _requestId = DateTime.now().microsecondsSinceEpoch.toString();
  int _minimum = 2;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _restaurantText.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createPod(
        widget.channel.id,
        _name.text,
        _minimum,
        _requestId,
        restaurantId: _mode == PodRestaurantMode.catalog && _temporary == null
            ? _restaurant?.id
            : null,
        restaurantText: _mode == PodRestaurantMode.direct
            ? _restaurantText.text
            : null,
        temporaryRestaurant: _mode == PodRestaurantMode.catalog
            ? _temporary
            : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '새 팟 만들기',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      tooltip: '팟 만들기 닫기',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('pod-name'),
                  controller: _name,
                  maxLength: 40,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '팟 이름 (필수)',
                    hintText: '예: 오늘은 따뜻한 국물',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '팟 이름을 입력해 주세요.' : null,
                ),
                const SizedBox(height: 16),
                const Text(
                  '식당 선택 또는 직접 입력',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<PodRestaurantMode>(
                  segments: const [
                    ButtonSegment(
                      value: PodRestaurantMode.catalog,
                      label: Text('등록 식당 선택'),
                    ),
                    ButtonSegment(
                      value: PodRestaurantMode.direct,
                      label: Text('직접 입력'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (v) => setState(() => _mode = v.single),
                ),
                const SizedBox(height: 12),
                if (_mode == PodRestaurantMode.catalog)
                  FormField<Restaurant>(
                    key: const Key('pod-restaurant-validation'),
                    validator: (_) => _restaurant == null && _temporary == null
                        ? '등록 식당을 선택하거나 임시 식당을 넣어 주세요.'
                        : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('pod-restaurant'),
                          onPressed: _busy
                              ? null
                              : () async {
                                  final selected =
                                      await featureSheet<Restaurant>(
                                        context,
                                        SearchSheet(
                                          repository: widget.repository,
                                          allowManual: false,
                                          showFavorites: true,
                                          locationAccess: widget.locationAccess,
                                          onTemporaryRestaurant: (temporary) {
                                            if (mounted) {
                                              setState(() {
                                                _temporary = temporary;
                                                _restaurant = null;
                                              });
                                            }
                                          },
                                        ),
                                      );
                                  if (selected != null && mounted) {
                                    setState(() {
                                      _restaurant = selected;
                                      _temporary = null;
                                    });
                                    field.didChange(selected);
                                  }
                                },
                          icon: const Icon(Icons.search),
                          label: Text(
                            _temporary != null
                                ? '${_temporary!.name} [임시]'
                                : _restaurant?.name ?? '식당 이름 입력·검색',
                          ),
                        ),
                        if (_restaurant != null || _temporary != null)
                          Text(
                            _temporary?.address ?? _restaurant!.address,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        if (_temporary != null)
                          const Text(
                            '팟을 만들면 제보도 함께 접수해요. DB 등록 전까지 이 팟에서만 임시로 사용해요.',
                            style: TextStyle(fontSize: 12, color: orange),
                          ),
                        if (field.hasError)
                          Text(
                            field.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  TextFormField(
                    key: const Key('pod-restaurant-text'),
                    controller: _restaurantText,
                    enabled: !_busy,
                    maxLength: 100,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '원하는 내용 (선택)',
                      hintText: '예: 회사 앞 분식집 / 오늘은 피크닉',
                      helperText: '입력한 내용은 이 팟에만 표시해요.',
                    ),
                  ),
                TextButton.icon(
                  key: const Key('report-pod-restaurant'),
                  onPressed: _busy
                      ? null
                      : () async {
                          final temporary =
                              await featureSheet<TemporaryRestaurant>(
                                context,
                                RestaurantReportForm(
                                  repository: widget.repository,
                                  allowTemporary: true,
                                ),
                              );
                          if (temporary != null && mounted) {
                            setState(() {
                              _temporary = temporary;
                              _restaurant = null;
                              _mode = PodRestaurantMode.catalog;
                            });
                          }
                        },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('DB에 없는 식당 제보·임시 사용'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const Key('pod-minimum'),
                  menuMaxHeight: 320,
                  initialValue: _minimum,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '최소 모집 인원'),
                  items: [
                    for (var i = 2; i <= 100; i++)
                      DropdownMenuItem(value: i, child: Text('$i명')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _minimum = v!),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: orange)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('save-pod'),
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? '만드는 중…' : '팟 만들고 참여하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class RestaurantReportForm extends StatefulWidget {
  const RestaurantReportForm({
    required this.repository,
    this.allowTemporary = false,
    super.key,
  });
  final AppRepository repository;
  final bool allowTemporary;
  @override
  State<RestaurantReportForm> createState() => _RestaurantReportFormState();
}

class _RestaurantReportFormState extends State<RestaurantReportForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _address = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '운영자에게 식당 제보',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                widget.allowTemporary
                    ? '이번 팟에서 임시로 쓰거나 제보만 할 수 있어요. 임시 사용은 팟 생성과 함께 제보되며, 운영자 확인 전에는 공용 DB·내 식당에 저장되지 않아요.'
                    : '운영자가 확인해 DB에 등록한 뒤 검색·선택할 수 있어요.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                maxLength: 80,
                key: const Key('report-restaurant-name'),
                decoration: const InputDecoration(labelText: '식당 이름'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '식당 이름을 입력해 주세요.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                maxLength: 200,
                key: const Key('report-restaurant-address'),
                decoration: const InputDecoration(labelText: '주소·위치'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '위치를 입력해 주세요.' : null,
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: orange)),
              const SizedBox(height: 16),
              if (widget.allowTemporary) ...[
                FilledButton(
                  key: const Key('use-temporary-restaurant'),
                  onPressed: _busy
                      ? null
                      : () {
                          if (!_form.currentState!.validate()) return;
                          Navigator.pop(
                            context,
                            TemporaryRestaurant(
                              _name.text.trim(),
                              _address.text.trim(),
                            ),
                          );
                        },
                  child: const Text('임시로 넣기'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('report-restaurant-only'),
                onPressed: _busy
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        setState(() => _busy = true);
                        try {
                          await widget.repository.reportRestaurant(
                            _name.text,
                            _address.text,
                            '음식점',
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('제보했어요. 운영자 확인 후 등록돼요.'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _busy = false;
                              _error = '$e';
                            });
                          }
                        }
                      },
                child: Text(
                  _busy
                      ? '접수 중…'
                      : widget.allowTemporary
                      ? '그냥 제보만 하기'
                      : '제보 보내기',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
