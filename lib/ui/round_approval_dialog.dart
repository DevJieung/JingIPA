import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../domain/models.dart';
import 'theme.dart';

class RoundApprovalDialog extends StatefulWidget {
  const RoundApprovalDialog({
    required this.repository,
    required this.channel,
    super.key,
  });
  final AppRepository repository;
  final LunchChannel channel;
  @override
  State<RoundApprovalDialog> createState() => _RoundApprovalDialogState();
}

class _RoundApprovalDialogState extends State<RoundApprovalDialog> {
  bool _sending = false, _closing = false;
  String? _error;
  late final _requestId = widget.repository
      .roundFor(widget.channel.id)
      ?.transition
      ?.id;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final pending = widget.repository.roundFor(widget.channel.id)?.transition;
      if (pending == null ||
          pending.id != _requestId ||
          widget.repository.user == null) {
        if (!_closing) {
          _closing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
        return const AlertDialog(content: Text('동의 결과를 반영했어요.'));
      }
      final reveal = pending.phase == RoundPhase.submission;
      return AlertDialog(
        key: const Key('round-approval-dialog'),
        title: Text(reveal ? '식당 공개 동의' : '최종 확정 동의'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.channel.name,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Text(
                '${pending.requiredCount}명 중 ${pending.approvedCount}명 완료',
                key: const Key('approval-count'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: pending.requiredCount == 0
                    ? 1
                    : pending.approvedCount / pending.requiredCount,
              ),
              const SizedBox(height: 16),
              Text(
                reveal
                    ? '참여를 선택한 참여자가 모두 동의하면 Round2로 넘어가요.'
                    : '참여를 선택한 참여자가 모두 동의하면 최종 확정해요.',
              ),
              const SizedBox(height: 8),
              Text(
                pending.approved
                    ? '동의했어요. 다른 참여자의 동의를 기다려요.'
                    : '계속 선택할 수 있어요. 동의 후 선택을 바꾸면 다시 동의해 주세요.',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: const Text('계속 선택하기'),
          ),
          if (pending.required)
            FilledButton(
              key: const Key('approve-transition'),
              onPressed: _sending || pending.approved
                  ? null
                  : () async {
                      setState(() {
                        _sending = true;
                        _error = null;
                      });
                      try {
                        await widget.repository.approveRoundTransition(
                          widget.channel.id,
                          pending.id,
                          pending.phase,
                        );
                      } catch (error) {
                        if (mounted) {
                          setState(
                            () => _error = error is LunchException
                                ? error.message
                                : '동의하지 못했어요. 다시 시도해 주세요.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _sending = false);
                      }
                    },
              child: Text(
                pending.approved
                    ? '동의 완료'
                    : _sending
                    ? '처리 중…'
                    : '동의',
              ),
            ),
        ],
      );
    },
  );
}
