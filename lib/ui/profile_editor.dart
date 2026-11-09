import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import 'theme.dart';
import 'name_guide.dart';

class EmojiAvatar extends StatelessWidget {
  const EmojiAvatar(this.emoji, {this.size = 48, super.key});
  final String emoji;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: sageSurface,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Text(
      emoji,
      style: TextStyle(
        fontFamily: 'NotoColorEmoji',
        fontSize: size * .56,
        height: 1.2,
      ),
    ),
  );
}

Future<void> editProfile(BuildContext context, AppRepository repository) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ProfileEditor(repository: repository),
    );

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({required this.repository, super.key});
  final AppRepository repository;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.repository.user!.name);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.updateName(_name.text);
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '내 프로필 편집',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '프로필 편집 닫기',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const NameSetupIntro(),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('profile-name'),
                controller: _name,
                maxLength: 20,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '이름'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '이름을 입력해 주세요.' : null,
              ),
              // 2026-11-09: no profile emoji. A fixed emoji let colleagues
              // learn who was who; emojis are now picked per round.
              const Text(
                '프로필에는 이모지가 없어요. 라운드마다 모두 코끼리로 시작하고, 식당 정하기의 대기실에서 그 라운드에만 쓸 이모지를 골라요.',
                key: Key('profile-emoji-note'),
                style: TextStyle(fontSize: 13, color: muted, height: 1.5),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: orange)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('save-profile'),
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '저장 중…' : '프로필 저장'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
