import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../domain/models.dart';
import 'theme.dart';

String cutoffTime(DateTime time, DateTime now) {
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final prefix = day == today ? '오늘' : '내일';
  return '$prefix ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class RoundCutoffForm extends StatefulWidget {
  const RoundCutoffForm({
    required this.repository,
    required this.onSave,
    this.round,
    super.key,
  });
  final AppRepository repository;
  final RoundView? round;
  final Future<void> Function(DateTime revealAt, DateTime endsAt) onSave;

  @override
  State<RoundCutoffForm> createState() => _RoundCutoffFormState();
}

class _RoundCutoffFormState extends State<RoundCutoffForm> {
  late DateTime revealAt, endsAt;
  String? error;
  bool saving = false;
  bool get first => widget.round?.phase != RoundPhase.adjusting;

  @override
  void initState() {
    super.initState();
    final now = widget.repository.now;
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    final round = widget.round;
    revealAt = round != null && !round.manualControl
        ? round.revealAt
        : nextMinute.add(const Duration(minutes: 14));
    endsAt = round != null && !round.manualControl
        ? round.endsAt
        : (first ? revealAt : nextMinute).add(const Duration(minutes: 10));
  }

  Future<void> pick(bool reveal) async {
    final initial = reveal ? revealAt : endsAt;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: reveal ? 'Round1 마감 · 식당 공개 시각' : 'Round2 마감 · 최종 확정 시각',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    final now = widget.repository.now;
    var time = DateTime(
      now.year,
      now.month,
      now.day,
      selected.hour,
      selected.minute,
    );
    if (!time.isAfter(now)) time = time.add(const Duration(days: 1));
    setState(() {
      error = null;
      if (reveal) {
        final duration = endsAt.difference(revealAt);
        revealAt = time;
        endsAt = time.add(duration);
      } else {
        endsAt = time;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.round == null ? '새 라운드 · 마감 시간 정하기' : '라운드 마감 시간 정하기',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          widget.round == null
              ? '라운드를 열면 내가 라운드장이 돼요. 식당 공개와 최종 확정 시각을 정해 주세요.'
              : '라운드장이 정한 시각에 자동으로 진행해요. 참여자의 동의는 필요하지 않아요.',
          style: const TextStyle(color: forest, height: 1.6),
        ),
        const SizedBox(height: 20),
        if (first) ...[
          OutlinedButton(
            key: const Key('round1-cutoff'),
            onPressed: saving ? null : () => pick(true),
            child: Text(
              'Round1 마감 · ${cutoffTime(revealAt, widget.repository.now)}',
            ),
          ),
          const Text(
            '이 시각부터 다른 사람들의 식당과 인원수가 보여요.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
        ],
        OutlinedButton(
          key: const Key('round2-cutoff'),
          onPressed: saving ? null : () => pick(false),
          child: Text(
            'Round2 마감 · ${cutoffTime(endsAt, widget.repository.now)}',
          ),
        ),
        const Text(
          '이 시각에 선택이 끝나고 같은 식당의 동료 이름이 보여요.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        const Text(
          'Round2는 1~120분으로 정해 주세요. 미정으로 마감해도 마지막 팟 합류가 가능해요.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              key: const Key('cutoff-error'),
              style: const TextStyle(color: orange),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: Key(widget.round == null ? 'start-round' : 'save-round-cutoffs'),
          onPressed: saving
              ? null
              : () async {
                  final now = widget.repository.now;
                  final duration = endsAt.difference(first ? revealAt : now);
                  if ((first &&
                          (!revealAt.isAfter(now) ||
                              revealAt.difference(now) >
                                  const Duration(hours: 24))) ||
                      duration < const Duration(minutes: 1) ||
                      duration > const Duration(minutes: 120)) {
                    setState(
                      () => error = '마감 시간을 다시 확인해 주세요. Round2는 1~120분이어야 해요.',
                    );
                    return;
                  }
                  setState(() => saving = true);
                  await widget.onSave(revealAt, endsAt);
                  if (mounted) setState(() => saving = false);
                },
          child: Text(widget.round == null ? '마감 시간 정하고 라운드 시작' : '마감 시간 저장'),
        ),
      ],
    ),
  );
}
