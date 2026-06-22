import 'dart:math' as math;

import 'package:flutter/material.dart';

const _kTeal = Color(0xFF0F6E56);
const _kInk = Color(0xFF0F2E26);

/// A single wagon-wheel shot: normalized field coords (0..1) + run value.
class WagonShot {
  const WagonShot({required this.x, required this.y, required this.runs});
  final double x;
  final double y;
  final int runs;
}

/// The cricket wagon wheel. Orientation (agreed with the user): the batter's
/// wicket is at the TOP and the bowler at the BOTTOM; for a right-handed bat the
/// off side is on the LEFT and the on side on the RIGHT. Shots radiate from the
/// batter's end.
///
/// - Capture: pass [onTap]; a tap reports normalized (x, y) + zone (1-8).
/// - Display: pass [shots]; a line is drawn from the batter to each.
class WagonField extends StatelessWidget {
  const WagonField({super.key, this.shots = const [], this.onTap});

  final List<WagonShot> shots;
  final void Function(double x, double y, int zone)? onTap;

  /// Batter's end (top-centre), where shots radiate from. Normalized.
  static const Offset batter = Offset(0.5, 0.16);

  /// 8 zones of 45 degrees, clockwise from straight-down (toward the bowler).
  static int zoneFor(double x, double y) {
    var a = math.atan2(x - batter.dx, y - batter.dy); // 0 = straight down
    if (a < 0) a += 2 * math.pi;
    return (a / (math.pi / 4)).floor() % 8 + 1;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.maxWidth;
          Widget field = CustomPaint(
            size: Size(side, side),
            painter: _WagonPainter(shots),
          );
          if (onTap != null) {
            field = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final nx = (d.localPosition.dx / side).clamp(0.0, 1.0);
                final ny = (d.localPosition.dy / side).clamp(0.0, 1.0);
                onTap!(nx, ny, zoneFor(nx, ny));
              },
              child: field,
            );
          }
          return field;
        },
      ),
    );
  }
}

class _WagonPainter extends CustomPainter {
  _WagonPainter(this.shots);
  final List<WagonShot> shots;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final center = Offset(w / 2, w / 2);
    final r = w / 2 - 2;
    final batter = Offset(WagonField.batter.dx * w, WagonField.batter.dy * w);

    canvas.drawCircle(
        center, r, Paint()..color = const Color(0xFFEAF3EF));
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _kTeal.withValues(alpha: 0.5));
    canvas.drawCircle(
        center,
        r * 0.55,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _kTeal.withValues(alpha: 0.22));

    // zone spokes from the batter
    final spoke = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final ang = math.pi / 2 + i * (math.pi / 4);
      canvas.drawLine(
        batter,
        Offset(batter.dx + math.cos(ang) * r * 1.5,
            batter.dy + math.sin(ang) * r * 1.5),
        spoke,
      );
    }

    // pitch + wicket (batter top, bowler bottom)
    final pitchW = w * 0.05;
    canvas.drawRect(
      Rect.fromLTRB(
          center.dx - pitchW / 2, batter.dy, center.dx + pitchW / 2, w * 0.84),
      Paint()..color = const Color(0xFFD8C9A8),
    );
    canvas.drawLine(Offset(center.dx, batter.dy - 5),
        Offset(center.dx, batter.dy + 5), Paint()..color = _kInk..strokeWidth = 2);

    _label(canvas, 'OFF', Offset(w * 0.12, batter.dy));
    _label(canvas, 'ON', Offset(w * 0.85, batter.dy));

    for (final s in shots) {
      final p = Offset(s.x * w, s.y * w);
      final color = _runColor(s.runs);
      canvas.drawLine(
        batter,
        p,
        Paint()
          ..strokeWidth = s.runs >= 4 ? 2.5 : 1.5
          ..color = color,
      );
      if (s.runs >= 4) canvas.drawCircle(p, 3, Paint()..color = color);
    }
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.black38, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  Color _runColor(int runs) {
    if (runs >= 6) return _kInk;
    if (runs >= 4) return _kTeal;
    if (runs >= 2) return Colors.black54;
    return Colors.black38;
  }

  @override
  bool shouldRepaint(covariant _WagonPainter old) => old.shots != shots;
}
