part of '../strip_card.dart';

class _MasterSocket extends StatefulWidget {
  final AppState state;
  final Strip strip;
  const _MasterSocket({required this.state, required this.strip});

  @override
  State<_MasterSocket> createState() => _MasterSocketState();
}

// hold the master, it stretches into a capsule; slide right for "all on", left for "all off", lift to pick.
// Lifting in the middle cancels. All off offers only "all on", all on only "all off", mixed both.
class _MasterSocketState extends State<_MasterSocket> {
  AppState get state => widget.state;
  bool _open = false;
  bool _canOn = false, _canOff = false;
  double _dx = 0;
  int _side = 0; // 1 = all on (right), -1 = all off (left)

  double get _capW {
    final avail = MediaQuery.sizeOf(context).width - 84;
    final both = math.min(310.0, avail);
    return _canOn && _canOff ? both : math.min(196.0, both);
  }

  // where the capsule sits: centred on the socket, or stretched to the one side it offers
  double get _shift => _canOn && _canOff ? 0 : (_capW - 64) / 2 * (_canOn ? 1 : -1);

  void _start() {
    final s = widget.strip;
    if (!s.online || state.isPending(s.mac, 0)) return;
    setState(() {
      _canOn = s.onCount < 4;
      _canOff = s.onCount > 0;
      _open = true;
      _dx = 0;
      _side = 0;
    });
    HapticFeedback.mediumImpact();
  }

  void _move(Offset o) {
    if (!_open) return;
    final reach = _canOn && _canOff ? _capW / 2 - 38 : _capW - 70;
    final dx = o.dx.clamp(_canOff ? -reach : 0.0, _canOn ? reach : 0.0);
    final side = dx > 46 ? 1 : (dx < -46 ? -1 : 0);
    if (side != _side) HapticFeedback.selectionClick();
    setState(() {
      _dx = dx;
      _side = side;
    });
  }

  void _end() {
    if (!_open) return;
    final side = _side;
    setState(() {
      _open = false;
      _dx = 0;
      _side = 0;
    });
    final s = widget.strip;
    if (side == 1) guardedAllOn(context, state, s);
    if (side == -1) guardedAllOff(context, state, s);
  }

  Widget _capsule() {
    final w = _capW;
    Widget side(bool on) {
      final hot = _side == (on ? 1 : -1);
      final color = on ? C.accent : C.danger;
      final icon = Icon(on ? Icons.power_settings_new : Icons.block, size: 17, color: hot ? color : color.withValues(alpha: 0.55));
      final text = Text(on ? t('bio_all_on') : t('bio_all_off'),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: hot ? color : color.withValues(alpha: 0.55)));
      return AnimatedScale(
        scale: hot ? 1.06 : 1,
        duration: const Duration(milliseconds: 150),
        child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: on ? [text, const SizedBox(width: 6), icon] : [icon, const SizedBox(width: 6), text]),
      );
    }

    return Positioned(
      left: (64 - w) / 2 + _shift,
      top: 0,
      width: w,
      height: 64,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: C.surface2.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: C.accent.withValues(alpha: 0.22)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
            gradient: _side == 0
                ? null
                : LinearGradient(
                    begin: _side == 1 ? Alignment.centerRight : Alignment.centerLeft,
                    end: Alignment.center,
                    colors: [(_side == 1 ? C.accent : C.danger).withValues(alpha: 0.18), C.surface2.withValues(alpha: 0.97)],
                  ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(textDirection: TextDirection.ltr, children: [
            if (_canOff) side(false),
            const Spacer(),
            if (_canOn) side(true),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strip;
    final online = s.online;
    final allOn = s.onCount == 4;
    final allOff = s.onCount == 0;
    final mixed = !allOn && !allOff;
    final on = online && (allOn || mixed);
    final pending = state.isPending(s.mac, 0);
    
    final load = on ? (s.livePower / kStripMaxW).clamp(0.0, 1.0) : 0.0;
    final String lbl = _open
        ? (_side == 1
            ? (Tr.isAr ? 'سيب لتشغيل الكل' : 'Release for all on')
            : _side == -1
                ? (Tr.isAr ? 'سيب لإيقاف الكل' : 'Release for all off')
                : (_canOn && _canOff
                    ? (Tr.isAr ? 'اسحب يمين أو شمال' : 'Slide right or left')
                    : _canOn
                        ? (Tr.isAr ? 'اسحب يمين لتشغيل الكل' : 'Slide right for all on')
                        : (Tr.isAr ? 'اسحب شمال لإيقاف الكل' : 'Slide left for all off')))
        : (allOn ? t('master_all_on') : (allOff ? t('master_all_off') : t('master_n_of_4', {'a': s.onCount})));

    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressMoveUpdate: (d) => _move(d.offsetFromOrigin),
      onLongPressEnd: (_) => _end(),
      onLongPressCancel: () {
        if (_open) setState(() => _open = false);
      },
      child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: pending ? null : () {
        if (!online) return;
        if (allOn) {
          guardedAllOff(context, state, s);
        } else {
          guardedAllOn(context, state, s);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(children: [
          // what is set on the whole strip (schedules, rules, timers, fingerprint, child lock) shows on the master,
          // like the outlets show theirs
          if (state.requiresBio(s.mac, 0) || s.masterLock || badgesFor(state, s, null, size: 12).isNotEmpty)
            SizedBox(
              height: 14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ...badgesFor(state, s, null, size: 12),
                  if (state.requiresBio(s.mac, 0))
                    Tooltip(
                      message: Tr.isAr ? 'يحتاج بصمة' : 'Biometric protected',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Icon(Icons.fingerprint, size: 12, color: C.accent),
                      ),
                    ),
                  if (s.masterLock)
                    Tooltip(
                      message: Tr.isAr ? 'قفل الأطفال على المشترك كله' : 'Child lock on the whole strip',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Icon(Icons.lock, size: 12, color: C.muted),
                      ),
                    ),
                ]),
              ),
            ),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            tween: Tween(end: load),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => SizedBox(
              width: 64,
              height: 64,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                if (_open) _capsule(),
                AnimatedContainer(
                  duration: Duration(milliseconds: _open ? 0 : 220),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(_dx, 0, 0),
                  child: Stack(alignment: Alignment.center, children: [
                    _HaloSpin(
                      running: on,
                      builder: (spin) => CustomPaint(size: const Size(64, 64), painter: _SocketPainter(
                        on: on, load: v, level: loadLevel(s.livePower, kStripMaxW), hot: s.maxTemp >= 60, dark: C.dark,
                        isMaster: true, mixed: mixed, spin: spin,
                      )),
                    ),
                    if (pending) SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Text(lbl, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _open ? C.accent : (on ? C.text : C.textSoft))),
        ]),
      ),
      ),
    );
  }
}

class _Socket extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Outlet outlet;
  const _Socket({required this.state, required this.strip, required this.outlet});

  @override
  Widget build(BuildContext context) {
    final o = outlet;
    final on = strip.online && o.on;
    final pending = state.isPending(strip.mac, o.n);
    final badges = badgesFor(state, strip, o, size: 12);
    final load = on ? (o.powerW / kOutletMaxW).clamp(0.0, 1.0) : 0.0;
    final currentAmps = o.amps(strip.voltage);
    final isAmpWarn = o.ampLimit > 0 && currentAmps >= (o.ampLimit * 0.85);
    final isTempWarn = o.tempC >= 55;
    final baseLevel = loadLevel(o.powerW, kOutletMaxW);
    final effLevel = (isAmpWarn || isTempWarn) ? math.max(baseLevel, 2) : baseLevel;
    final effHot = o.tempC >= 60 || (o.ampLimit > 0 && currentAmps >= o.ampLimit);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: pending ? null : () => guardedSwitch(context, state, strip, o, !o.on),
      onLongPress: () => openOutletSheet(context, state, strip.mac, o.n),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(children: [
          SizedBox(
            height: 14,
            child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: badges)),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(end: load),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => SizedBox(
              width: 64,
              height: 64,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size(64, 64), painter: _SocketPainter(on: on, load: v, level: effLevel, hot: effHot, dark: C.dark)),
                if (pending) SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (state.outletIcon(strip.mac, o.n).isNotEmpty) ...[
              FishaIcon(icon: state.outletIcon(strip.mac, o.n), size: 12, color: on ? C.text : C.textSoft),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(state.outletName(strip, o.n),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? C.text : C.textSoft)),
            ),
          ]),
          Text(
            on ? '${o.powerW.toStringAsFixed(o.powerW < 10 ? 1 : 0)} W' : (strip.online ? t('off') : '—'),
            textDirection: TextDirection.ltr,
            style: on ? mono(11, color: loadColor(o.powerW, kOutletMaxW), weight: FontWeight.w500) : TextStyle(fontSize: 11, color: C.faint),
          ),
          if (strip.online)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.thermostat, size: 11, color: tempColor(o.tempC)),
              Text('${o.tempC}°C', textDirection: TextDirection.ltr, style: mono(10.5, color: tempColor(o.tempC), weight: FontWeight.w500)),
            ]),
        ]),
      ),
    );
  }
}

/// Socket face (Schuko style) with a load ring.
class _SocketPainter extends CustomPainter {
  final bool on, hot, dark, isMaster, mixed;
  final double load;
  final int level;
  final double spin; // 0..1, the travelling highlight on the master's load halo
  _SocketPainter({required this.on, required this.load, required this.level, required this.hot, required this.dark, this.isMaster = false, this.mixed = false, this.spin = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringColor = hot ? C.danger : levelColor(level);
    // track
    canvas.drawCircle(c, r - 3, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = C.border);
    if (isMaster && on) {
      // load halo: the ring measures the strip's real draw against its 3500 W limit,
      // orange from 70 %, red from 90 % (or when it runs hot)
      final haloColor = level == 0 && !hot ? C.accent : ringColor;
      canvas.drawCircle(c, r - 6, Paint()
        ..color = haloColor.withValues(alpha: 0.08 + 0.22 * load)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      // the ring used a flat solid color here while every outlet fades it with a SweepGradient — that made
      // the master button noticeably more vivid than the outlets and hid the gradient detail. Same treatment now.
      final sweep = 2 * math.pi * math.max(0.04, load);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 3),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: -math.pi / 2 + sweep,
            colors: [Color.lerp(haloColor, C.surface, 0.35)!, haloColor],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      final a = -math.pi / 2 + 2 * math.pi * spin;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (r - 3), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.75));
    }
    if (on && !isMaster) {
      // glow
      canvas.drawCircle(c, r - 6, Paint()
        ..color = ringColor.withValues(alpha: 0.22)   // back to the clear glow of a switched-on socket
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      // load arc
      final sweep = 2 * math.pi * math.max(0.12, load);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 3),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: -math.pi / 2 + sweep,
            colors: [Color.lerp(ringColor, C.surface, 0.35)!, ringColor],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
    // face
    final face = r - 9;
    final bool innerOn = on && !mixed;
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..shader = RadialGradient(
          colors: innerOn
              ? (isMaster
                  // the master's face was too solid a green and swallowed the power icon
                  ? [ringColor.withValues(alpha: dark ? 0.16 : 0.12), dark ? C.surface2 : C.surface]
                  : [ringColor.withValues(alpha: dark ? 0.35 : 0.25), dark ? C.tileOn : C.accentBg])
              : (dark ? [C.surface2, C.tile] : [C.surface, C.miniOff]),
        ).createShader(Rect.fromCircle(center: c, radius: face)),
    );
    canvas.drawCircle(c, face, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = innerOn ? ringColor.withValues(alpha: 0.6) : C.border);
    
    // sunken look: the face darkens toward its rim, like a socket set into the strip
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..shader = RadialGradient(
          stops: const [0.68, 1.0],
          colors: [const Color(0x00000000), Color.fromRGBO(0, 0, 0, dark ? 0.38 : 0.16)],
        ).createShader(Rect.fromCircle(center: c, radius: face)),
    );
    final holeColor = innerOn ? Color.lerp(ringColor, const Color(0xFF000000), 0.6)! : (dark ? const Color(0xFF05080E) : C.faint);
    
    if (isMaster) {
      final iconColor = mixed || innerOn ? (innerOn ? ringColor : C.accent) : holeColor;
      final iconStr = String.fromCharCode(Icons.power_settings_new.codePoint);
      final tp = TextPainter(
        text: TextSpan(text: iconStr, style: TextStyle(fontFamily: Icons.power_settings_new.fontFamily, fontSize: face * 0.9, color: iconColor)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    } else {
      // pins and earth clips sit at 45°, like the sockets on the real MTTL-W01
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(math.pi / 4);
      canvas.translate(-c.dx, -c.dy);
      // two pin holes
      final hole = Paint()..color = holeColor;
      canvas.drawCircle(c.translate(-face * 0.38, 0), face * 0.13, hole);
      canvas.drawCircle(c.translate(face * 0.38, 0), face * 0.13, hole);
      // earth clips
      final clip = Paint()
        ..color = innerOn ? ringColor.withValues(alpha: 0.8) : C.faint
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c.translate(-face * 0.12, -face * 0.82), c.translate(face * 0.12, -face * 0.82), clip);
      canvas.drawLine(c.translate(-face * 0.12, face * 0.82), c.translate(face * 0.12, face * 0.82), clip);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SocketPainter old) => true; // cheap, and picks up theme changes
}

/// Drives the slow travelling highlight on the master's load halo while anything is on.
class _HaloSpin extends StatefulWidget {
  final bool running;
  final Widget Function(double spin) builder;
  const _HaloSpin({required this.running, required this.builder});

  @override
  State<_HaloSpin> createState() => _HaloSpinState();
}

class _HaloSpinState extends State<_HaloSpin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.running) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _HaloSpin old) {
    super.didUpdateWidget(old);
    if (widget.running && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.running && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => widget.builder(_c.value));
}
