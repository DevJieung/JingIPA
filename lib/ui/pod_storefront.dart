import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

const shopGreen = Color(0xFF7E9B8E);
const shopCream = Color(0xFFF5F7F0);
const shopSignSurface = Color(0xFFF0F5F1);

/// Painted at the card's full width so the awning and sign form one storefront.
class PodAwning extends StatelessWidget {
  const PodAwning({this.archived = false, super.key});
  final bool archived;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 38,
      child: CustomPaint(painter: _AwningPainter(archived)),
    ),
  );
}

class _AwningPainter extends CustomPainter {
  const _AwningPainter(this.archived);
  final bool archived;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = archived ? const Color(0xFF98A69D) : shopGreen;
    final light = archived ? historyCardSurface : shopCream;
    final paint = Paint();
    final width = size.width / 8;
    canvas.drawRect(
      Rect.fromLTWH(0, 28, size.width, 7),
      paint..color = forest.withValues(alpha: .05),
    );
    for (var i = 0; i < 8; i++) {
      final x = i * width;
      paint.color = i.isEven ? light : dark;
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + width, 0)
          ..lineTo(x + width, 26)
          ..quadraticBezierTo(x + width, 33, x + width / 2, 33)
          ..quadraticBezierTo(x, 33, x, 26)
          ..close(),
        paint,
      );
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, 25),
        Paint()
          ..color = forest.withValues(alpha: .08)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_AwningPainter oldDelegate) =>
      archived != oldDelegate.archived;
}

/// Six seats per row, two visible rows, with anonymous occupants and one door.
/// More rows scroll inside the room without moving the cards or action buttons.
class PodSeatingRoom extends StatefulWidget {
  const PodSeatingRoom({
    required this.minimum,
    required this.count,
    required this.selected,
    required this.emoji,
    this.animate = true,
    this.archived = false,
    super.key,
  });
  final int minimum, count;
  final bool selected, animate, archived;
  final String emoji;

  static double heightForWidth(double width) => (width - 77) / 3 + 31;

  @override
  State<PodSeatingRoom> createState() => _PodSeatingRoomState();
}

class _PodSeatingRoomState extends State<PodSeatingRoom>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController(keepScrollOffset: false);
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
    value: 1,
  );
  Timer? _walkTimer;
  bool _entering = true;
  bool _motionEnabled = false;
  int _walker = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  @override
  void didUpdateWidget(PodSeatingRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _walker = 0;
      _motion.value = 1;
    }
    if (oldWidget.selected != widget.selected ||
        oldWidget.count != widget.count ||
        oldWidget.animate != widget.animate ||
        oldWidget.archived != widget.archived) {
      _configureMotion(enter: widget.selected && !oldWidget.selected);
    }
  }

  void _configureMotion({bool enter = false}) {
    final enabled =
        widget.animate &&
        !widget.archived &&
        widget.count > 0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    final start = enabled && (!_motionEnabled || enter);
    _motionEnabled = enabled;
    _walkTimer?.cancel();
    if (!enabled) {
      _motion.stop();
      _motion.value = 1;
      return;
    }
    if (start) {
      _entering = true;
      _walker = 0;
      _motion.forward(from: 0);
    }
    // Leave a quiet interval between short walks; no perpetual frame loop.
    _walkTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted ||
          !_motionEnabled ||
          !TickerMode.valuesOf(context).enabled ||
          (_scroll.hasClients && _scroll.offset > 0)) {
        return;
      }
      _entering = false;
      _walker = widget.selected
          ? 0
          : (_walker + 1) % math.min(widget.count, 12);
      _motion.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _walkTimer?.cancel();
    _motion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slots = math.max(12, math.max(widget.minimum, widget.count));
    final rows = (slots / 6).ceil();
    final total = rows * 6;
    return Semantics(
      label:
          '모집 인원: 최소 ${widget.minimum}명, 현재 ${widget.count}명. '
          '$total자리, $rows줄${rows > 2 ? ", 아래로 스크롤해서 확인" : ""}',
      child: LayoutBuilder(
        builder: (context, box) {
          const doorWidth = 34.0;
          const aisle = 12.0;
          const gap = 5.0;
          final seat = (box.maxWidth - doorWidth - aisle - gap * 5 - 6) / 6;
          final stride = seat + gap;
          final viewport = stride * 2 - gap;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: _motion,
                builder: (context, _) => SizedBox(
                  height: viewport,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: doorWidth,
                            child: ExcludeSemantics(
                              child: CustomPaint(
                                key: const Key('pod-painted-door'),
                                painter: _DoorPainter(widget.archived),
                              ),
                            ),
                          ),
                          const SizedBox(width: aisle),
                          Expanded(
                            child: Scrollbar(
                              controller: _scroll,
                              thumbVisibility: rows > 2,
                              thickness: 3,
                              radius: const Radius.circular(3),
                              child:
                                  NotificationListener<ScrollStartNotification>(
                                    onNotification: (_) {
                                      _motion.value = 1;
                                      return false;
                                    },
                                    child: SingleChildScrollView(
                                      key: const Key('pod-seats-scroll'),
                                      controller: _scroll,
                                      primary: false,
                                      padding: const EdgeInsets.only(right: 6),
                                      child: SizedBox(
                                        height: stride * rows - gap,
                                        child: Stack(
                                          children: [
                                            for (var i = 0; i < total; i++)
                                              Positioned(
                                                left: (i % 6) * stride,
                                                top: (i ~/ 6) * stride,
                                                width: seat,
                                                height: seat,
                                                child: _seat(i, seat),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.count > 0 &&
                          _motionEnabled &&
                          _motion.value < 1)
                        _walkingEmoji(seat, stride),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 18,
                child: Row(
                  children: [
                    _legend(orange, '최소 인원'),
                    const SizedBox(width: 10),
                    _legend(forest, '추가 참여'),
                    const Spacer(),
                    if (rows > 2)
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: muted,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _legend(Color color, String label) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 10,
            color: widget.archived ? historyInk : muted,
          ),
        ),
      ],
    ),
  );

  Widget _seat(int i, double side) {
    final occupied = i < widget.count;
    final minimum = i < widget.minimum;
    final color = minimum ? orange : forest;
    final walking = _motionEnabled && _motion.value < 1 && i == _walker;
    return ExcludeSemantics(
      child: Container(
        key: ValueKey('pod-seat-$i'),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: occupied
              ? color.withValues(alpha: .09)
              : Colors.white.withValues(alpha: .55),
          border: Border.all(
            color: minimum || occupied ? color : line,
            width: minimum ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: occupied && !walking ? _emoji(i, side) : null,
      ),
    );
  }

  Widget _emoji(int index, double side) => Text(
    widget.selected && index == 0 ? widget.emoji : '🐘',
    key: widget.selected && index == 0 ? const Key('pod-own-emoji') : null,
    textScaler: TextScaler.noScaling,
    style: TextStyle(
      fontFamily: 'NotoColorEmoji',
      fontSize: side * .76,
      height: 1,
    ),
  );

  Widget _walkingEmoji(double seat, double stride) {
    final target = Offset(46 + (_walker % 6) * stride, (_walker ~/ 6) * stride);
    final doorway = Offset(4, stride * .5);
    final progress = _motion.value;
    final travel = _entering
        ? Curves.easeOutCubic.transform(progress)
        : 1 - math.pow(math.sin(math.pi * progress), 2).toDouble();
    final position = Offset.lerp(doorway, target, travel)!;
    return Positioned(
      left: position.dx,
      top: position.dy - math.sin(progress * math.pi * 6).abs() * 2,
      width: seat,
      height: seat,
      child: ExcludeSemantics(child: Center(child: _emoji(_walker, seat))),
    );
  }
}

class _DoorPainter extends CustomPainter {
  const _DoorPainter(this.archived);
  final bool archived;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = archived ? const Color(0xFF98A69D) : shopGreen;
    final rect = Rect.fromLTWH(1, 2, size.width - 2, size.height - 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = frame,
    );
    final glass = Rect.fromLTWH(6, 7, size.width - 12, size.height * .47);
    canvas.drawRRect(
      RRect.fromRectAndRadius(glass, const Radius.circular(4)),
      Paint()..color = shopCream,
    );
    final shine = Paint()
      ..color = Colors.white.withValues(alpha: .65)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(10, 13),
      Offset(size.width - 11, glass.bottom - 7),
      shine,
    );
    canvas.drawLine(
      Offset(15, 13),
      Offset(size.width - 10, glass.bottom - 13),
      shine,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 10, size.height * .6, 3, 10),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFF2CC83),
    );
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = frame.withValues(alpha: .5)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DoorPainter oldDelegate) =>
      archived != oldDelegate.archived;
}
