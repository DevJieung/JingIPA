import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'theme.dart';

const redPerson = Color(0xFFD94B48);
const greyPerson = Color(0xFFB0B7B0);

class PersonStrip extends StatelessWidget {
  const PersonStrip({
    required this.total,
    required this.mine,
    required this.red,
    this.colorCounts = const {},
    super.key,
  });
  final int total, mine, red;
  final Map<String, int> colorCounts;
  @override
  Widget build(BuildContext context) {
    final counts = colorCounts.isEmpty
        ? <String, int>{if (red > 0) 'D94B48': red}
        : colorCounts;
    var remaining = (total - mine).clamp(0, total);
    final marked = <Color>[];
    for (final entry in counts.entries.where((e) => validPersonColor(e.key))) {
      final count = entry.value.clamp(0, remaining);
      remaining -= count;
      marked.addAll(
        List.filled(count, Color(int.parse('FF${entry.key}', radix: 16))),
      );
    }
    final greyCount = remaining;
    final colors = [
      for (var i = 0; i < mine; i++) ink,
      ...marked,
      for (var i = 0; i < greyCount; i++) greyPerson,
    ];
    final colorLabel = counts.entries
        .where((e) => e.value > 0)
        .map((e) => '${personColorName(e.key)} ${e.value}명')
        .join(', ');
    return Semantics(
      label:
          '나 $mine명, ${colorLabel.isEmpty ? '지정 색상 0명' : colorLabel}, 일반 동료 $greyCount명',
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          child: Wrap(
            key: ValueKey('$mine:$counts:$greyCount'),
            spacing: 1,
            runSpacing: 2,
            children: [
              for (final color in colors.take(12))
                Icon(Icons.person_rounded, size: 19, color: color),
              if (colors.length > 12)
                Text(
                  '+${colors.length - 12}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              if (colors.isEmpty)
                const Text(
                  '아직 선택한 동료가 없어요',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PeopleLegend extends StatelessWidget {
  const PeopleLegend({
    required this.showRed,
    this.colors = const {},
    super.key,
  });
  final bool showRed;
  final Set<String> colors;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 5,
    children: [
      _item('나', ink),
      _item('동료', greyPerson),
      if (showRed)
        for (final color in colors.where(validPersonColor))
          _item(
            personColorName(color),
            Color(int.parse('FF$color', radix: 16)),
          ),
    ],
  );
  Widget _item(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.person_rounded, color: color, size: 17),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(fontSize: 10, color: muted)),
    ],
  );
}

/// Animates net changes by color; does not receive or preserve individual IDs.
class LivePeopleOptions extends StatefulWidget {
  const LivePeopleOptions({
    required this.options,
    required this.myRestaurantId,
    required this.cardBuilder,
    super.key,
  });
  final List<RestaurantCount> options;
  final String? myRestaurantId;
  final Widget Function(RestaurantCount) cardBuilder;
  @override
  State<LivePeopleOptions> createState() => _LivePeopleOptionsState();
}

class _LivePeopleOptionsState extends State<LivePeopleOptions> {
  final Map<String, GlobalKey> _keys = {};
  final Set<OverlayEntry> _flights = {};
  Map<String, int> _counts(RestaurantCount option, String? mine) {
    final own = option.restaurant.id == mine ? 1 : 0;
    final marked = option.displayColors.values.fold(0, (a, b) => a + b);
    return {
      'self': own,
      ...option.displayColors,
      'grey': (option.count - own - marked).clamp(0, option.count),
    };
  }

  @override
  void didUpdateWidget(covariant LivePeopleOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = {
      for (final o in oldWidget.options)
        o.restaurant.id: _counts(o, oldWidget.myRestaurantId),
    };
    final next = {
      for (final o in widget.options)
        o.restaurant.id: _counts(o, widget.myRestaurantId),
    };
    final moves = <(String, String, Color)>[];
    final colorKeys = {
      'self',
      'grey',
      for (final row in [...old.values, ...next.values]) ...row.keys,
    };
    for (final color in colorKeys) {
      final from = <String>[], to = <String>[];
      for (final id in old.keys.where(next.containsKey)) {
        final delta = (next[id]![color] ?? 0) - (old[id]![color] ?? 0);
        for (var i = 0; i < math.min(delta.abs(), 6); i++) {
          if (delta < 0) {
            from.add(id);
          } else if (delta > 0) {
            to.add(id);
          }
        }
      }
      for (
        var i = 0;
        i < math.min(from.length, to.length) && moves.length < 6;
        i++
      ) {
        moves.add((
          from[i],
          to[i],
          color == 'self'
              ? ink
              : color == 'grey'
              ? greyPerson
              : Color(int.parse('FF$color', radix: 16)),
        ));
      }
    }
    if (moves.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
        for (final (from, to, color) in moves) {
          _fly(from, to, color);
        }
      });
    }
  }

  void _finish(OverlayEntry entry) {
    if (_flights.remove(entry)) {
      entry.remove();
      entry.dispose();
    }
  }

  void _fly(String from, String to, Color color) {
    final a = _keys[from]?.currentContext?.findRenderObject();
    final b = _keys[to]?.currentContext?.findRenderObject();
    final overlay = Overlay.of(context, rootOverlay: true);
    final root = overlay.context.findRenderObject();
    if (a is! RenderBox || b is! RenderBox || root is! RenderBox) return;
    final start = a.localToGlobal(
      Offset(a.size.width - 65, a.size.height - 25),
      ancestor: root,
    );
    final end = b.localToGlobal(
      Offset(b.size.width - 65, b.size.height - 25),
      ancestor: root,
    );
    final height = MediaQuery.sizeOf(context).height;
    if (start.dy < 55 ||
        end.dy < 55 ||
        start.dy > height - 70 ||
        end.dy > height - 70) {
      return;
    }
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlyingPerson(
        start: start,
        end: end,
        color: color,
        onEnd: () => _finish(entry),
      ),
    );
    _flights.add(entry);
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => ResponsiveCards(
    minWidth: 250,
    spacing: 14,
    children: [
      for (final option in widget.options)
        KeyedSubtree(
          key: _keys.putIfAbsent(option.restaurant.id, () => GlobalKey()),
          child: widget.cardBuilder(option),
        ),
    ],
  );
  @override
  void dispose() {
    for (final entry in _flights.toList()) {
      _finish(entry);
    }
    super.dispose();
  }
}

class _FlyingPerson extends StatefulWidget {
  const _FlyingPerson({
    required this.start,
    required this.end,
    required this.color,
    required this.onEnd,
  });
  final Offset start, end;
  final Color color;
  final VoidCallback onEnd;
  @override
  State<_FlyingPerson> createState() => _FlyingPersonState();
}

class _FlyingPersonState extends State<_FlyingPerson>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 480),
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) widget.onEnd();
          })
          ..forward();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, _) {
      final t = Curves.easeInOutCubic.transform(_controller.value);
      final position =
          Offset.lerp(widget.start, widget.end, t)! -
          Offset(0, math.sin(t * math.pi) * 22);
      return Positioned(
        left: position.dx,
        top: position.dy,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: paper,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_rounded, size: 25, color: widget.color),
            ),
          ),
        ),
      );
    },
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
