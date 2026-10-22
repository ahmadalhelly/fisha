import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class WifiArcs extends StatelessWidget {
  final int? rssi;
  const WifiArcs({super.key, this.rssi});

  @override
  Widget build(BuildContext context) {
    if (rssi == null) {
      return Icon(Icons.signal_wifi_off, size: 16, color: C.faint);
    }
    
    int litLevel;
    Color color;
    if (rssi! >= -55) {
      litLevel = 3;
      color = C.accent.withValues(alpha: 0.8);   // strong: the app's mint, softened
    } else if (rssi! >= -67) {
      litLevel = 2;
      color = C.accent2;                        // good: sky blue
    } else if (rssi! >= -75) {
      litLevel = 1;
      color = C.warn;                           // weak: amber
    } else {
      litLevel = 0;
      color = C.danger;                         // poor: red
    }

    return CustomPaint(
      size: const Size(16, 16),
      painter: _WifiPainter(litLevel: litLevel, color: color),
    );
  }
}

class _WifiPainter extends CustomPainter {
  final int litLevel;
  final Color color;

  _WifiPainter({required this.litLevel, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final unlitColor = color.withValues(alpha: 0.25);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.height * 0.13;

    final center = Offset(size.width / 2, size.height * 0.88);
    
    // dot
    paint.style = PaintingStyle.fill;
    paint.color = color;
    canvas.drawCircle(center, size.height * 0.1, paint);

    // arcs
    paint.style = PaintingStyle.stroke;
    
    final maxR = (size.width / 2 - paint.strokeWidth / 2) / math.sin(50 * math.pi / 180);
    final radii = [maxR * 0.36, maxR * 0.68, maxR];
    for (int i = 0; i < 3; i++) {
      paint.color = (i + 1) <= litLevel ? color : unlitColor;
      final radius = radii[i];
      final rect = Rect.fromCircle(center: center, radius: radius);
      
      const startAngle = -140 * (math.pi / 180);
      const sweepAngle = 100 * (math.pi / 180);
      
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(_WifiPainter oldDelegate) {
    return oldDelegate.litLevel != litLevel || oldDelegate.color != color;
  }
}
