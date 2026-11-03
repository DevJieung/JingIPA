import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../domain/models.dart';
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
  late String _emoji = widget.repository.user!.emoji;
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
      await widget.repository.updateProfile(_name.text, _emoji);
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
              const SizedBox(height: 12),
              Row(
                children: [
                  EmojiAvatar(_emoji, size: 48),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '나를 표현하는 이모지',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '대기실에서는 실명이 아닌 이모지로 보여요!',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final emoji in profileEmojis)
                    Semantics(
                      selected: _emoji == emoji,
                      child: IconButton(
                        key: Key('emoji-$emoji'),
                        tooltip: '프로필 $emoji',
                        style: IconButton.styleFrom(
                          backgroundColor: _emoji == emoji ? lime : paper,
                        ),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _emoji = emoji),
                        icon: EmojiAvatar(emoji, size: 40),
                      ),
                    ),
                ],
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
