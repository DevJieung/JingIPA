import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'theme.dart';

class RoundCooldownDialog extends StatefulWidget {
  const RoundCooldownDialog({
    required this.availableAt,
    required this.now,
    super.key,
  });
  final DateTime availableAt;
  final DateTime Function() now;

  @override
  State<RoundCooldownDialog> createState() => _RoundCooldownDialogState();
}

class _RoundCooldownDialogState extends State<RoundCooldownDialog>
    with WidgetsBindingObserver {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('round-cooldown-dialog'),
    scrollable: true,
    title: const Text('새 라운드 대기'),
    content: Text(
      roundCooldownMessage(widget.availableAt, widget.now()),
      key: const Key('round-cooldown-countdown'),
      style: const TextStyle(color: orange, fontWeight: FontWeight.w800),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('확인'),
      ),
    ],
  );
}
