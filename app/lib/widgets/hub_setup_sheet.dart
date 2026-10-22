import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../services/hub_setup.dart';
import '../theme.dart';
import 'common.dart';

String _x(String ar, String en) => Tr.isAr ? ar : en;

/// Hub setup (design: pairing card + ring). A card rises over the screen ("we found Fisha Hub near you");
/// "Set it up" grows the same card to full screen, where only the Wi-Fi password is asked (the network name is the
/// one the phone is on; address and hub password sit under "advanced" with their defaults).
Future<void> showHubSetup(BuildContext context, AppState s, {String? hubSsid}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => HubSetupSheet(state: s, hubSsid: hubSsid),
    );

/// Looks for a hub in setup mode now and then while the home screen is open (only when location is already allowed),
/// and offers the card once per hub per app run.
class HubSetupWatcher {
  static final _offered = <String>{};
  static Timer? _t;
  static bool _open = false;

  static void start(BuildContext context, AppState s) {
    if (!HubSetup.supported || _t != null) return;
    Future<void> tick() async {
      if (_open || !context.mounted || s.settings.isShared) return;
      // already talking to a hub: nothing to offer (a hub that lost its Wi-Fi leaves the app offline, so it still shows)
      if (s.mode != ConnMode.offline && s.settings.hubId.isNotEmpty) return;
      if (!await HubSetup.permission()) return;
      final l = await HubSetup.scanHubs();
      final fresh = l.where((x) => !_offered.contains(x)).toList();
      if (fresh.isEmpty || !context.mounted) return;
      _offered.add(fresh.first);
      _open = true;
      await showHubSetup(context, s, hubSsid: fresh.first);
      _open = false;
    }

    _t = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    Future.delayed(const Duration(seconds: 4), tick);
  }

  static void stop() {
    _t?.cancel();
    _t = null;
  }
}

class HubSetupSheet extends StatefulWidget {
  final AppState state;
  final String? hubSsid;
  const HubSetupSheet({super.key, required this.state, this.hubSsid});

  @override
  State<HubSetupSheet> createState() => _HubSetupSheetState();
}

class _HubSetupSheetState extends State<HubSetupSheet> {
  AppState get s => widget.state;
  bool _full = false, _adv = false, _busy = false, _done = false;
  // the hub took the Wi-Fi but this phone has not seen it yet (still switching networks, or away from home)
  bool _pending = false;
  String _pendingIp = '';
  double _pct = 0;
  String _say = '', _sub = '';
  String? _err;
  final _steps = <String>[];
  String? _hub;
  final _home = TextEditingController(), _pw = TextEditingController(), _ip = TextEditingController(), _ota = TextEditingController();
  bool _homeKnown = false;
  bool _showPw = false, _showOta = false;
  // opened from Settings while this phone is already linked to a working hub
  late bool _linked;
  // the hub found nearby is this phone's own hub (its Wi-Fi changed): Fisha-Hub-XXXX = last 4 of its MAC
  bool get _mine {
    final id = s.settings.hubId.toUpperCase();
    return _hub != null && id.length >= 4 && _hub!.toUpperCase().endsWith(id.substring(id.length - 4));
  }

  @override
  void initState() {
    super.initState();
    _hub = widget.hubSsid;
    _linked = widget.hubSsid == null && s.mode != ConnMode.offline && s.settings.hubId.isNotEmpty;
    _ip.text = s.settings.localHost.isNotEmpty ? s.settings.localHost : '192.168.1.100';
  }

  @override
  void dispose() {
    _home.dispose();
    _pw.dispose();
    _ip.dispose();
    _ota.dispose();
    super.dispose();
  }

  Future<void> _expand() async {
    _linked = false;
    await HubSetup.permission(ask: true);
    final ssid = await HubSetup.currentSsid();
    if (!mounted) return;
    setState(() {
      _full = true;
      _home.text = ssid.startsWith('Fisha-Hub-') ? '' : ssid;
      _homeKnown = _home.text.isNotEmpty;
      _say = _x('على أنهي شبكة؟', 'Which network?');
      _sub = _homeKnown ? _x('دي الشبكة اللي موبايلك عليها دلوقتي', 'The network your phone is on now') : _x('اكتب اسم واي فاي البيت', 'Type your home Wi-Fi name');
    });
  }

  void _step(String text, double pct) {
    if (!mounted) return;
    setState(() {
      _steps.add(text);
      _say = text;
      _pct = pct;
    });
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = msg;
      _say = _x('على أنهي شبكة؟', 'Which network?');
      _sub = '';
    });
  }

  Future<void> _go() async {
    final home = _home.text.trim(), pw = _pw.text;
    if (home.isEmpty) return _fail(_x('اكتب اسم واي فاي البيت.', 'Type the home Wi-Fi name.'));
    if (pw.isNotEmpty && pw.length < 8) return _fail(_x('باسورد الواي فاي 8 حروف على الأقل.', 'The Wi-Fi password has at least 8 characters.'));
    if (_ota.text.isNotEmpty && _ota.text.length < 8) return _fail(_x('باسورد الهاب 8 حروف على الأقل، أو سيبه فاضي.', 'Hub password: 8+ characters, or leave it empty.'));
    setState(() {
      _busy = true;
      _err = null;
      _steps.clear();
      _pct = 0;
      _sub = _x('متقفلش التطبيق', 'Keep the app open');
    });

    // 1. Google first: the hub's network has no internet
    if (s.googleEmail.isEmpty) {
      final e = await s.googleSignIn();
      if (e != null || s.googleEmail.isEmpty) return _fail(e ?? _x('لازم تسجّل بجيميل الأول.', 'Sign in with Google first.'));
    }
    final who = s.userName.isNotEmpty ? s.userName : s.googleEmail.split('@').first;
    _step(s.settings.isShared ? who : _x('$who هو المالك', '$who is the owner'), 20);

    // 2. the hub's own network
    var hub = _hub;
    if (hub == null) {
      final l = await HubSetup.scanHubs();
      if (l.isNotEmpty) hub = l.first;
    }
    if (hub == null) {
      return _fail(_x('مش لاقي شبكة الهاب. وصّل الهاب بالكهربا واستنى دقيقة، وقرّب الموبايل منه.',
          'Can\'t find the hub\'s network. Power the hub, wait a minute and bring the phone closer.'));
    }
    final j = await HubSetup.joinHub(hub);
    if (j == 'fail') return _fail(_x('ماقدرتش أدخل على شبكة الهاب. جرّب تاني.', 'Could not join the hub\'s network. Try again.'));
    final info = await HubSetup.info();
    if (info == null) {
      await HubSetup.releaseHub();
      return _fail(j == 'manual'
          ? _x('افتح إعدادات الواي فاي في الموبايل، ادخل على $hub، وارجع دوس «وصّل الهاب».', 'Open the phone\'s Wi-Fi settings, join $hub, then come back and tap Connect.')
          : _x('الهاب مش بيرد. جرّب تاني.', 'The hub is not answering. Try again.'));
    }
    _step(_x('اتصلنا بالهاب', 'Connected to the hub'), 45);

    // 3. everything in one request
    final mac = (info['hub'] ?? '').toString();
    final res = await HubSetup.send({
      'ssid': home,
      'pass': pw,
      'ip': _ip.text.trim(),
      'email': s.googleEmail,
      'model': s.phoneModel,
      if (_ota.text.isNotEmpty) 'ota': _ota.text,
      'key': s.settings.ownerKey,
      'cur': s.otaPass.isNotEmpty ? s.otaPass : 'fisha-$mac',
    });
    await HubSetup.releaseHub();
    if (res.error != null) {
      return _fail(switch (res.error) {
        'claim_window' => _x('تسجيل المالك متاح أول 10 دقايق بعد تشغيل الهاب. افصله ورجّعه وجرّب تاني.', 'Claiming is open for 10 minutes after power-on. Power-cycle the hub and retry.'),
        'owner' => _x('الهاب ده ليه مالك تاني. لازم موبايل المالك يعمل الإعداد.', 'This hub already has an owner. Use the owner\'s phone.'),
        'ip' => _x('عنوان الهاب لازم يبقى على شبكة البيت (192.168.1.x).', 'The hub address must be on the home network (192.168.1.x).'),
        'wifi' || 'wifi_pass' => _x('اسم أو باسورد الواي فاي مش مقبول.', 'The Wi-Fi name or password was refused.'),
        _ => _x('الإرسال للهاب فشل. جرّب تاني.', 'Sending to the hub failed. Try again.'),
      });
    }
    if (_ota.text.isNotEmpty) await s.setOtaPass(_ota.text);
    _step(_x('الواي فاي اتبعت', 'Wi-Fi sent'), 70);
    final ip = res.ip.isNotEmpty ? res.ip : _ip.text.trim();
    await s.applyHubSetup(hub: res.hub.isNotEmpty ? res.hub : mac, ip: ip, key: res.key);

    // 4. back home: wait for the hub to show up on the home network
    _step(_x('الهاب بيدخل على $home', 'The hub is joining $home'), 90);
    _pendingIp = ip;
    if (await _waitForHub(ip, const Duration(seconds: 150))) return _finish(ip);
    if (!mounted) return;
    // the hub is set up; only this phone could not see it yet. Say so and let the owner check again, instead of
    // leaving the ring at 90% with a failure message.
    setState(() {
      _busy = false;
      _pending = true;
      _err = null;
      _pct = 90;
      _say = _x('الهاب اتجهّز', 'The hub is set up');
      _sub = _x('بس الموبايل لسه ما شافوش على $ip. اتأكد إن الموبايل على واي فاي البيت وبعدين دوس «اتأكد تاني».',
          'but this phone cannot see it at $ip yet. Make sure the phone is on your home Wi-Fi, then tap Check again.');
    });
  }

  /// true once the hub answers on the home network, or the cloud already reports it online
  Future<bool> _waitForHub(String ip, Duration limit, {bool cloudNow = false}) async {
    final t0 = DateTime.now();
    var cloudTried = false;
    if (cloudNow) {
      await s.restart();
      cloudTried = true;
    }
    while (DateTime.now().difference(t0) < limit) {
      if (!mounted) return false;
      if (await s.hubAnswersAt(ip)) return true;
      if (cloudTried && s.settings.hubId.isNotEmpty && s.mode != ConnMode.offline) return true;
      // after ~40 s try the cloud link once: the hub may be up while this phone is still on another network
      if (!cloudTried && DateTime.now().difference(t0) > const Duration(seconds: 40)) {
        cloudTried = true;
        await s.restart();
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  Future<void> _recheck() async {
    setState(() {
      _busy = true;
      _sub = _x('بيدوّر على الهاب…', 'Looking for the hub…');
    });
    final ok = await _waitForHub(_pendingIp, const Duration(seconds: 30), cloudNow: true);
    if (!mounted) return;
    if (ok) {
      setState(() => _pending = false);
      return _finish(_pendingIp);
    }
    setState(() {
      _busy = false;
      _sub = _x('لسه مش ظاهر على $_pendingIp. تأكد إن الموبايل على واي فاي البيت وجرّب تاني. لو الباسورد كان غلط، الهاب هيفتح شبكته بعد دقيقة وتقدر تعيد الإعداد.',
          'Still not visible at $_pendingIp. Make sure the phone is on your home Wi-Fi and try again. If the password was wrong, the hub reopens its network in a minute and you can set it up again.');
    });
  }

  Future<void> _finish(String ip) async {
    _step(_x('ظهر على $ip', 'Online at $ip'), 100);
    await s.restart();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = true;
      _say = _x('أهلاً بيك في Fisha', 'Welcome to Fisha');
      _sub = _x('يلا نضيف أول مشترك', 'Now add your first strip');
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    // the ring changes size but always stays a true circle (width == height)
    final ring = !_full ? 132.0 : (_adv || inset > 0 ? 110.0 : 180.0);
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 520),
        curve: const Cubic(.2, .8, .2, 1),
        height: _full ? h * 0.94 : 400,
        margin: EdgeInsets.all(_full ? 0 : 10),
        decoration: BoxDecoration(
          color: C.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(_full ? 28 : 30),
          border: Border.all(color: C.border),
        ),
        child: SafeArea(
          top: false,
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  width: ring,
                  height: ring,
                  child: _Ring(pct: _pct, full: _full, done: _done || _linked),
                ),
                const SizedBox(height: 14),
                Text(
                    _full
                        ? _say
                        : _linked
                            ? _x('إنت مربوط بالهاب فعلاً', 'You are already linked to your hub')
                            : _mine
                                ? _x('الهاب بتاعك مستني شبكة', 'Your hub is waiting for a network')
                                : _x('لقينا Fisha Hub جنبك', 'Fisha Hub found nearby'),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    _full
                        ? _sub
                        : _linked
                            ? _x('الهاب ${s.settings.hubId.toUpperCase()} شغال على ${s.settings.localHost}${s.mode == ConnMode.cloud ? ' (من برا البيت)' : ''}.',
                                'Hub ${s.settings.hubId.toUpperCase()} is running at ${s.settings.localHost}${s.mode == ConnMode.cloud ? ' (away from home)' : ''}.')
                            : _mine
                                ? _x('شكله فقد الواي فاي (اتغيّر الراوتر أو الباسورد؟). ادّيله الشبكة تاني.', 'It lost its Wi-Fi (new router or password?). Give it the network again.')
                                : _x('الهاب الجديد مستني يتجهّز، وأنت هتبقى المالك.', 'Your new hub is waiting to be set up. You will be its owner.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.muted, fontSize: 13)),
                const SizedBox(height: 10),
                if (_steps.isNotEmpty)
                  Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                    for (final x in _steps)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: C.accent.withValues(alpha: 0.4))),
                        child: Text('✓ $x', style: TextStyle(color: C.accent, fontSize: 11.5)),
                      ),
                  ]),
                Expanded(child: _full && !_busy && !_done && !_pending ? _form() : const SizedBox()),
                if (_linked)
                  TextButton(
                    onPressed: _expand,
                    child: Text(_x('تجهيز هاب تاني أو تغيير شبكة الهاب', 'Set up another hub, or change its Wi-Fi'), style: TextStyle(color: C.muted, fontSize: 12.5)),
                  ),
                if (_err != null) ...[
                  Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: C.danger, fontSize: 12.5, height: 1.5)),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: _done
                      ? primaryButton(_x('تمام', 'Done'), () => Navigator.pop(context), icon: Icons.check)
                      : _pending
                          ? primaryButton(_busy ? _x('بيتأكد…', 'Checking…') : _x('اتأكد تاني', 'Check again'), _busy ? null : _recheck, icon: Icons.refresh)
                      : _linked
                          ? primaryButton(_x('تمام', 'OK'), () => Navigator.pop(context), icon: Icons.check)
                          : !_full
                          ? primaryButton(_x('جهّزه', 'Set it up'), _expand, icon: Icons.bolt)
                          : primaryButton(_busy ? _x('بيوصّل…', 'Connecting…') : _x('وصّل الهاب', 'Connect the hub'), _busy ? null : _go, icon: Icons.wifi),
                ),
              ]),
            ),
            if (!_busy)
              PositionedDirectional(
                top: 12,
                end: 12,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: C.muted, size: 20),
                  style: IconButton.styleFrom(backgroundColor: C.surface2),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _eye(bool shown, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        tooltip: shown ? _x('إخفاء', 'Hide') : _x('إظهار', 'Show'),
        icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: C.muted, size: 20),
      );

  Widget _form() => SingleChildScrollView(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_homeKnown)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: C.surface2.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
              child: Row(children: [
                Icon(Icons.wifi, color: C.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_home.text, textDirection: TextDirection.ltr, textAlign: TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w700))),
                GestureDetector(
                  onTap: () => setState(() => _homeKnown = false),
                  child: Text(_x('غيّر', 'Change'), style: TextStyle(color: C.accent, fontSize: 12)),
                ),
              ]),
            )
          else
            TextField(controller: _home, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: _x('اسم واي فاي البيت', 'Home Wi-Fi name'))),
          const SizedBox(height: 10),
          TextField(
            controller: _pw,
            obscureText: !_showPw,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
                suffixIcon: _eye(_showPw, () => setState(() => _showPw = !_showPw)),
                labelText: _x('باسورد ${_home.text.isEmpty ? 'الواي فاي' : _home.text}', 'Password for ${_home.text.isEmpty ? 'the Wi-Fi' : _home.text}')),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _adv = !_adv),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Text(_x('إعدادات متقدمة', 'Advanced'), style: TextStyle(color: C.muted, fontSize: 12.5)),
                const Spacer(),
                Text(_x('الـIP وباسورد الهاب', 'IP and hub password'), style: TextStyle(color: C.faint, fontSize: 12)),
                Icon(_adv ? Icons.expand_less : Icons.expand_more, color: C.faint, size: 18),
              ]),
            ),
          ),
          if (_adv) ...[
            TextField(
                controller: _ip,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _x('عنوان الهاب (نفس صفحة الاتصال)', 'Hub address (same as the Connection page)'))),
            const SizedBox(height: 10),
            TextField(
                controller: _ota,
                obscureText: !_showOta,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                    suffixIcon: _eye(_showOta, () => setState(() => _showOta = !_showOta)),
                    labelText: _x('باسورد الهاب للطوارئ', 'Hub emergency password'),
                    helperText: _x('سيبه فاضي = fisha- وبعده MAC الهاب', 'Empty = fisha- followed by the hub MAC'))),
          ],
        ]),
      );
}

class _Ring extends StatelessWidget {
  final double pct;
  final bool full, done;
  const _Ring({required this.pct, required this.full, required this.done});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final d = math.min(c.maxWidth, c.maxHeight);
        return Center(
          child: SizedBox(
            width: d,
            height: d,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: pct / 100),
              duration: const Duration(milliseconds: 800),
              curve: const Cubic(.2, .8, .2, 1),
              builder: (_, v, __) => CustomPaint(
                painter: _RingPainter(v),
                child: Padding(
                  padding: EdgeInsets.all(d * 0.17),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(center: Alignment(0, -0.3), colors: [Color(0xFF1D3050), Color(0xFF0B1424)]),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.14), blurRadius: 40)],
                    ),
                    child: Center(
                      child: full
                          ? FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: done
                                    ? Icon(Icons.check_rounded, color: C.accent, size: 44)
                                    : Text('${(v * 100).round()}%', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                              ),
                            )
                          : LoopLogo(size: d * 0.36),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
}

class _RingPainter extends CustomPainter {
  final double v;
  _RingPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 4;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withValues(alpha: 0.06)..style = PaintingStyle.stroke..strokeWidth = 5);
    if (v <= 0) return;
    final p = Paint()
      ..color = C.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v.clamp(0, 1), false, p);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v;
}
