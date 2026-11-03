import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ElephantScene { greeting, secret, together, favorite }

/// Resolution-independent brand artwork, shared by the web and Android builds.
class ElephantArt extends StatelessWidget {
  const ElephantArt({
    this.size = 120,
    this.scene = ElephantScene.greeting,
    this.headOnly = false,
    super.key,
  });

  final double size;
  final ElephantScene scene;
  final bool headOnly;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ElephantPainter(scene, headOnly)),
    ),
  );
}

class _ElephantPainter extends CustomPainter {
  _ElephantPainter(this.scene, this.headOnly);
  final ElephantScene scene;
  final bool headOnly;
  static const green = Color(0xFF2C4E3F);
  static const sage = Color(0xFFC6D7BE);
  static const peach = Color(0xFFECC1AB);
  static const cream = Color(0xFFF9F3DF);
  static const coral = Color(0xFFF17856);
  final _fill = Paint()..isAntiAlias = true;
  final _stroke = Paint()
    ..isAntiAlias = true
    ..color = green
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _path(Canvas c, Path path, Color color) {
    c.drawPath(path, _fill..color = color);
    c.drawPath(path, _stroke);
  }

  void _oval(Canvas c, Rect r, Color color, {bool outline = true}) {
    c.drawOval(r, _fill..color = color);
    if (outline) c.drawOval(r, _stroke);
  }

  void _rect(Canvas c, Rect r, Color color, {double radius = 5}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    c.drawRRect(rr, _fill..color = color);
    c.drawRRect(rr, _stroke);
  }

  void _elephant(
    Canvas c, {
    Color color = sage,
    bool mask = false,
    bool head = false,
  }) {
    if (!head) {
      _oval(c, const Rect.fromLTWH(29, 62, 43, 47), color);
      _oval(c, const Rect.fromLTWH(38, 76, 24, 24), cream, outline: false);
      _rect(c, const Rect.fromLTWH(31, 96, 15, 17), color, radius: 6);
      _rect(c, const Rect.fromLTWH(56, 96, 15, 17), color, radius: 6);
      _oval(c, const Rect.fromLTWH(19, 69, 17, 26), color);
      _oval(c, const Rect.fromLTWH(67, 68, 17, 26), color);
      c.drawPath(
        Path()
          ..moveTo(71, 92)
          ..quadraticBezierTo(87, 98, 85, 84),
        _stroke,
      );
    }
    // Broad ears and a long, curled trunk keep the small silhouette readable.
    _oval(c, const Rect.fromLTWH(9, 17, 33, 48), color);
    _oval(c, const Rect.fromLTWH(58, 17, 33, 48), color);
    _oval(c, const Rect.fromLTWH(15, 23, 23, 35), peach, outline: false);
    _oval(c, const Rect.fromLTWH(62, 23, 23, 35), peach, outline: false);
    _path(
      c,
      Path()
        ..moveTo(27, 37)
        ..cubicTo(26, 8, 72, 7, 74, 35)
        ..lineTo(75, 53)
        ..quadraticBezierTo(75, 68, 60, 71)
        ..lineTo(61, 82)
        ..cubicTo(62, 98, 42, 96, 43, 82)
        ..lineTo(44, 67)
        ..cubicTo(31, 69, 24, 60, 27, 37)
        ..close(),
      color,
    );
    if (mask) {
      _path(
        c,
        Path()
          ..moveTo(29, 37)
          ..quadraticBezierTo(49, 43, 72, 37)
          ..lineTo(70, 51)
          ..quadraticBezierTo(52, 62, 31, 51)
          ..close(),
        green,
      );
      _oval(c, const Rect.fromLTWH(34, 43, 12, 7), cream, outline: false);
      _oval(c, const Rect.fromLTWH(56, 43, 12, 7), cream, outline: false);
    }
    c.drawCircle(const Offset(40, 46), 1.8, _fill..color = green);
    c.drawCircle(const Offset(62, 46), 1.8, _fill..color = green);
    _oval(c, const Rect.fromLTWH(28, 54, 10, 5), peach, outline: false);
    _oval(c, const Rect.fromLTWH(65, 54, 10, 5), peach, outline: false);
    c.drawPath(
      Path()
        ..moveTo(37, 57)
        ..quadraticBezierTo(41, 62, 45, 58),
      _stroke,
    );
    c.drawPath(
      Path()
        ..moveTo(48, 79)
        ..lineTo(56, 79)
        ..moveTo(48, 83)
        ..lineTo(55, 83),
      _stroke,
    );
    c.drawPath(
      Path()
        ..moveTo(44, 19)
        ..quadraticBezierTo(42, 10, 49, 12)
        ..moveTo(49, 18)
        ..quadraticBezierTo(53, 7, 56, 14),
      _stroke,
    );
  }

  void _mini(Canvas c, double x, double y, double scale, Color color) {
    c.save();
    c.translate(x, y);
    c.scale(scale);
    _elephant(c, color: color);
    c.restore();
  }

  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 180, size.height / 180);
    if (headOnly) {
      c.translate(-2, -8);
      c.scale(1.83);
      _elephant(c, head: true);
      return;
    }
    switch (scene) {
      case ElephantScene.greeting:
        _oval(
          c,
          const Rect.fromLTWH(19, 36, 143, 132),
          const Color(0xFFF0F5EC),
          outline: false,
        );
        c.save();
        c.translate(35, 16);
        c.rotate(-.08);
        c.scale(1.15);
        _elephant(c);
        // A fork and spoon echo the supplied lunch mascot.
        c.drawPath(
          Path()
            ..moveTo(16, 61)
            ..lineTo(16, 94)
            ..moveTo(9, 54)
            ..lineTo(9, 64)
            ..quadraticBezierTo(16, 71, 23, 64)
            ..lineTo(23, 54)
            ..moveTo(16, 52)
            ..lineTo(16, 65),
          _stroke..strokeWidth = 2,
        );
        _oval(c, const Rect.fromLTWH(82, 49, 11, 17), cream);
        c.drawLine(const Offset(87, 65), const Offset(87, 94), _stroke);
        c.restore();
        _spark(c, const Offset(145, 33), 7);
        _spark(c, const Offset(22, 122), 4);
      case ElephantScene.secret:
        _oval(
          c,
          const Rect.fromLTWH(9, 18, 160, 151),
          const Color(0xFFF1F5ED),
          outline: false,
        );
        c.save();
        c.translate(23, 47);
        c.rotate(-.17);
        _rect(c, const Rect.fromLTWH(0, 0, 41, 53), cream);
        _oval(c, const Rect.fromLTWH(10, 8, 20, 19), sage, outline: false);
        c.drawLine(const Offset(8, 36), const Offset(32, 36), _stroke);
        c.drawLine(const Offset(8, 42), const Offset(25, 42), _stroke);
        c.restore();
        c.save();
        c.translate(125, 40);
        c.rotate(.15);
        _rect(c, const Rect.fromLTWH(0, 0, 37, 52), cream);
        _oval(c, const Rect.fromLTWH(10, 8, 17, 17), peach);
        c.drawLine(const Offset(8, 36), const Offset(29, 36), _stroke);
        c.drawLine(const Offset(8, 42), const Offset(24, 42), _stroke);
        c.restore();
        c.save();
        c.translate(44, 5);
        c.scale(.95);
        _elephant(c, mask: true);
        c.restore();
        _path(
          c,
          Path()
            ..moveTo(47, 111)
            ..lineTo(130, 111)
            ..lineTo(144, 130)
            ..lineTo(34, 130)
            ..close(),
          cream,
        );
        _rect(c, const Rect.fromLTWH(34, 130, 110, 43), cream, radius: 4);
        _rect(c, const Rect.fromLTWH(58, 119, 63, 4), green, radius: 2);
        _rect(c, const Rect.fromLTWH(45, 142, 88, 18), coral, radius: 9);
        _oval(c, const Rect.fromLTWH(53, 145, 9, 9), cream, outline: false);
        c.drawLine(const Offset(69, 151), const Offset(119, 151), _stroke);
      case ElephantScene.together:
        _oval(
          c,
          const Rect.fromLTWH(6, 24, 165, 143),
          const Color(0xFFF2F5EE),
          outline: false,
        );
        _mini(c, 0, 36, .54, sage);
        _mini(c, 29, 70, .5, peach);
        _mini(c, 1, 111, .4, const Color(0xFFCEDBDD));
        _rect(c, const Rect.fromLTWH(93, 74, 77, 86), cream, radius: 5);
        _path(
          c,
          Path()
            ..moveTo(98, 49)
            ..lineTo(163, 49)
            ..lineTo(175, 75)
            ..lineTo(87, 75)
            ..close(),
          sage,
        );
        for (var i = 0; i < 6; i++) {
          final x = 89 + i * 14.0;
          _path(
            c,
            Path()
              ..moveTo(99 + i * 11.0, 49)
              ..lineTo(110 + i * 11.0, 49)
              ..lineTo(x + 14, 75)
              ..lineTo(x, 75)
              ..close(),
            i.isEven ? green : cream,
          );
        }
        _mini(c, 95, 87, .32, const Color(0xFFCEDBDD));
        _mini(c, 137, 86, .32, sage);
        _rect(c, const Rect.fromLTWH(109, 127, 43, 6), peach, radius: 2);
        c.drawLine(
          const Offset(130, 133),
          const Offset(130, 156),
          _stroke..strokeWidth = 2,
        );
        c.drawPath(
          Path()
            ..moveTo(100, 125)
            ..lineTo(100, 150)
            ..lineTo(112, 150)
            ..moveTo(161, 125)
            ..lineTo(161, 150)
            ..lineTo(149, 150),
          _stroke,
        );
        _path(
          c,
          Path()
            ..moveTo(61, 115)
            ..lineTo(77, 115)
            ..lineTo(77, 109)
            ..lineTo(88, 121)
            ..lineTo(77, 133)
            ..lineTo(77, 126)
            ..lineTo(61, 126)
            ..close(),
          green,
        );
        _heart(c, const Offset(66, 34), 12);
      case ElephantScene.favorite:
        _oval(
          c,
          const Rect.fromLTWH(12, 29, 154, 139),
          const Color(0xFFF1F5ED),
          outline: false,
        );
        c.save();
        c.translate(35, 20);
        c.scale(1.1);
        _elephant(c);
        c.restore();
        _heart(c, const Offset(91, 116), 24);
    }
  }

  void _heart(Canvas c, Offset center, double size) {
    c.save();
    c.translate(center.dx, center.dy);
    c.scale(size / 20);
    final path = Path()
      ..moveTo(0, 16)
      ..cubicTo(-32, -4, -12, -25, 0, -11)
      ..cubicTo(12, -25, 32, -4, 0, 16)
      ..close();
    c.drawPath(path, _fill..color = coral);
    c.restore();
  }

  void _spark(Canvas c, Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final r = i.isEven ? radius : radius * .3;
      final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    c.drawPath(path, _fill..color = coral);
  }

  @override
  bool shouldRepaint(_ElephantPainter oldDelegate) =>
      scene != oldDelegate.scene || headOnly != oldDelegate.headOnly;
}

class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(20, 20), painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final rect = Rect.fromLTWH(2, 2, s.width - 4, s.height - 4);
    for (final arc in [
      (.78, 1.58, const Color(0xFF34A853)),
      (2.36, 1.0, const Color(0xFFFBBC05)),
      (3.36, 2.2, const Color(0xFFEA4335)),
      (-.05, .83, const Color(0xFF4285F4)),
    ]) {
      c.drawArc(rect, arc.$1, arc.$2, false, p..color = arc.$3);
    }
    c.drawLine(
      Offset(s.width / 2, s.height / 2),
      Offset(s.width - 1, s.height / 2),
      p..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
