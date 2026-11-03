import 'dart:ui' show SemanticsRole;
import 'package:flutter/material.dart';
import 'theme.dart';

class LoadNotice extends StatelessWidget {
  const LoadNotice({
    required this.message,
    this.failed = false,
    this.onRetry,
    super.key,
  });
  final String message;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Surface(
    child: Semantics(
      role: SemanticsRole.status,
      container: true,
      label: message,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ElephantArt(size: 80, scene: ElephantScene.together),
          const SizedBox(height: 12),
          ExcludeSemantics(child: Text(message, textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          if (failed)
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도'))
          else
            const SizedBox(width: 160, child: LinearProgressIndicator()),
        ],
      ),
    ),
  );
}
