import 'package:flutter/material.dart';
import 'name_guide.dart';
import '../domain/models.dart';

class GuestJoinDialog extends StatefulWidget {
  const GuestJoinDialog({super.key, required this.join, this.initialCode = ''});
  final Future<void> Function(String name, String code) join;
  final String initialCode;

  @override
  State<GuestJoinDialog> createState() => _GuestJoinDialogState();
}

class _GuestJoinDialogState extends State<GuestJoinDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _code = TextEditingController(text: widget.initialCode);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.join(_name.text.trim(), _code.text.trim());
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is LunchException
              ? error.message
              : '연결을 확인하고 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('비회원으로 참여하기'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('초대 코드로 모임에 바로 입장해요. 모집 중에는 팟을 만들고 참여·이동할 수 있어요.'),
              const SizedBox(height: 16),
              const NameGuideText(),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('guest-name'),
                controller: _name,
                enabled: !_busy,
                maxLength: 20,
                decoration: const InputDecoration(labelText: '동료가 알아볼 이름'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '이름을 입력해 주세요.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('guest-code'),
                controller: _code,
                enabled: !_busy,
                maxLength: 32,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: '초대 코드'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '동료에게 받은 초대 코드를 입력해 주세요.'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              const Text(
                '이름은 모임 구성원과 최종 확정 후 같은 식당의 동료에게 보여요.\n\n'
                '이 기기·브라우저에서 계속 참여할 수 있어요. 로그아웃·앱 삭제·브라우저 데이터 삭제 시 기록을 다시 찾지 못할 수 있어요. '
                '내 프로필에서 계정을 연결하면 기록을 이어갈 수 있어요.',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('닫기'),
        ),
        FilledButton(
          key: const Key('guest-join-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '참여 중…' : '이 모임에 참여하기'),
        ),
      ],
    ),
  );
}
