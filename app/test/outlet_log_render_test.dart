import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/app_state.dart';
import 'package:mttl_hub/screens/outlet_log_screen.dart';

// renders the outlet history with a sample log and writes a PNG (test/shots) to look at the layout
void main() {
  testWidgets('outlet history layout', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    int at(int dayBack, int h, int m) => DateTime(now.year, now.month, now.day - dayBack, h, m).millisecondsSinceEpoch ~/ 1000;
    final cycles = [
      {'n': 4, 'on': at(0, 0, 17), 'off': at(0, 1, 11), 'wh': 36, 'src': 0},
      {'n': 1, 'on': at(0, 0, 17), 'off': 0, 'wh': 6, 'src': 0},
      {'n': 2, 'on': at(0, 0, 17), 'off': 0, 'wh': 26, 'src': 1},
      {'n': 4, 'on': at(1, 23, 52), 'off': at(1, 23, 53), 'wh': 0, 'src': 1},
      {'n': 3, 'on': at(1, 20, 51), 'off': at(1, 21, 52), 'wh': 40, 'src': 0},
    ];
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: OutletLogScreen(state: AppState(), mac: 'AABBCCDDEEFF', outlet: 0, loader: (_) async => CmdResult(true, null, {'cycles': cycles})),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    late ui.Image img;
    await tester.runAsync(() async {
      img = await b.toImage(pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('test/shots').createSync(recursive: true);
      File('test/shots/outlet_log.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
