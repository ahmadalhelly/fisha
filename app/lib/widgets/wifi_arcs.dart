import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import 'strip_card.dart' show levelColor;

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
      color = levelColor(0);
    } else if (rssi! >= -67) {
      litLevel = 2;
      color = levelColor(1);
    } else if (rssi! >= -75) {
      litLevel = 1;
      color = levelColor(2);
    } else {
      litLevel = 0;
      color = levelColor(3);
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
      ..strokeWidth = 1.8;

    final center = Offset(size.width / 2, size.height - 2);
    
    // dot
    paint.style = PaintingStyle.fill;
    paint.color = color;
    canvas.drawCircle(center, 1.8, paint);

    // arcs
    paint.style = PaintingStyle.stroke;
    
    for (int i = 1; i <= 3; i++) {
      paint.color = i <= litLevel ? color : unlitColor;
      final radius = 1.8 + i * 3.5;
      final rect = Rect.fromCircle(center: center, radius: radius);
      
      // ~90 deg sweep, centered upwards
      // startAngle is -135 degrees (in radians)
      // sweepAngle is 90 degrees (in radians)
      const startAngle = -135 * (math.pi / 180);
      const sweepAngle = 90 * (math.pi / 180);
      
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(_WifiPainter oldDelegate) {
    return oldDelegate.litLevel != litLevel || oldDelegate.color != color;
  }
}
