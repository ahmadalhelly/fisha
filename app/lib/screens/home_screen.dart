import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/strip_card.dart';
import '../widgets/strip_mini.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onOpenSettings;
  const HomeScreen({super.key, required this.state, required this.onOpenSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final err = s.lastError;
    if (err != null && mounted) {
      s.clearError();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what جاية في الـ Sprints الجاية')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final strips = s.strips;
          final header = _header(context);
          final pad = const EdgeInsets.fromLTRB(18, 16, 18, 24);

          Widget body;
          if (strips.isEmpty) {
            body = ListView(padding: pad, children: [header, const SizedBox(height: 16), _empty()]);
          } else if (s.viewMode == ViewMode.grid) {
            body = ListView(
              padding: pad,
              children: [
                header,
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                  children: strips
                      .map((st) => StripMini(state: s, strip: st, onTap: () => s.setViewMode(ViewMode.list)))
                      .toList(),
                ),
              ],
            );
          } else if (s.sortMode == SortMode.manual && s.query.trim().isEmpty) {
            body = ReorderableListView.builder(
              padding: pad,
              header: Padding(padding: const EdgeInsets.only(bottom: 16), child: header),
              buildDefaultDragHandles: false,
              itemCount: strips.length,
              onReorder: s.reorder,
              itemBuilder: (context, i) => Padding(
                key: ValueKey(strips[i].mac),
                padding: const EdgeInsets.only(bottom: 14),
                child: StripCard(
                  state: s,
                  strip: strips[i],
                  dragHandle: ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.drag_indicator, color: C.faint, size: 20),
                    ),
                  ),
                ),
              ),
            );
          } else {
            body = ListView(
              padding: pad,
              children: [
                header,
                const SizedBox(height: 16),
                for (final st in strips)
                  Padding(padding: const EdgeInsets.only(bottom: 14), child: StripCard(state: s, strip: st)),
              ],
            );
          }
          return RefreshIndicator(color: C.accent, onRefresh: s.refresh, child: body);
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('البيت', style: TextStyle(fontSize: 13, color: C.muted)),
                  Text('مشتركاتي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            _modePill(),
          ],
        ),
        const SizedBox(height: 16),
        _summary(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _quick(Icons.bar_chart, 'الطاقة', () => _soon('شاشة الطاقة'))),
            const SizedBox(width: 8),
            Expanded(child: _quick(Icons.schedule, 'المواعيد', () => _soon('المواعيد'))),
            const SizedBox(width: 8),
            Expanded(child: _quick(Icons.bolt, 'الأتمتة', () => _soon('الأتمتة'))),
            const SizedBox(width: 8),
            Expanded(child: _quick(Icons.home_outlined, 'الغرف', () => _soon('الغرف'))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextField(
                  onChanged: s.setQuery,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'دوّر على مشترك أو مخرج',
                    prefixIcon: Icon(Icons.search, color: C.muted, size: 20),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _viewToggle(),
            const SizedBox(width: 8),
            _sortButton(),
          ],
        ),
      ],
    );
  }

  Widget _modePill() {
    final (label, color) = switch (s.mode) {
      ConnMode.local => ('محلي', C.green),
      ConnMode.cloud => ('عن بُعد', C.blue),
      ConnMode.offline => ('غير متصل', C.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: cardBox(radius: 999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: C.textSoft)),
        ],
      ),
    );
  }

  Widget _summary() {
    final v = s.voltage;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardBox(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('القدرة دلوقتي', style: TextStyle(fontSize: 13, color: C.muted)),
                    const SizedBox(height: 6),
                    Row(
                      textDirection: TextDirection.ltr,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(s.totalPower.toStringAsFixed(1), style: mono(42, color: C.accent)),
                        const SizedBox(width: 6),
                        Text('W', style: mono(16, color: C.muted, weight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(v == null ? '— V' : '${v.toStringAsFixed(0)} V',
                      textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(s.mode == ConnMode.local ? 'تحديث كل ثانيتين' : 'تحديث لحظي',
                      style: const TextStyle(fontSize: 12, color: C.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('${s.onlineCount}', 'مشترك متصل')),
              const SizedBox(width: 8),
              Expanded(child: _stat('${s.onCount}/${s.outletCount}', 'مخرج شغال')),
              const SizedBox(width: 8),
              Expanded(child: _stat(s.allStrips.isEmpty ? '—' : '${s.maxTemp}°C', 'أعلى حرارة')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, textDirection: TextDirection.ltr, style: mono(17)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
          ],
        ),
      );

  Widget _quick(IconData icon, String label, VoidCallback onTap) => Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
            child: Column(
              children: [
                Icon(icon, color: C.accent, size: 22),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  Widget _viewToggle() {
    Widget btn(ViewMode m, IconData icon, String tip) {
      final sel = s.viewMode == m;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => s.setViewMode(m),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: sel ? C.accentBg : Colors.transparent, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: sel ? C.accent : C.muted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: cardBox(radius: 14),
      child: Row(children: [
        btn(ViewMode.list, Icons.view_agenda_outlined, 'عرض القائمة'),
        btn(ViewMode.grid, Icons.grid_view, 'عرض الشبكة'),
      ]),
    );
  }

  Widget _sortButton() {
    const labels = {
      SortMode.manual: 'ترتيبي (بالسحب)',
      SortMode.power: 'الأعلى استهلاكًا',
      SortMode.name: 'بالاسم',
      SortMode.status: 'الأكتر شغال',
    };
    return PopupMenuButton<SortMode>(
      tooltip: 'ترتيب',
      color: C.surface2,
      onSelected: s.setSortMode,
      itemBuilder: (_) => [
        for (final e in labels.entries)
          CheckedPopupMenuItem(value: e.key, checked: s.sortMode == e.key, child: Text(e.value)),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: cardBox(radius: 14),
        child: const Icon(Icons.swap_vert, color: C.textSoft, size: 20),
      ),
    );
  }

  Widget _empty() {
    final st = s.settings;
    final String title;
    final String body;
    if (!st.hasLocal && !st.hasCloud) {
      title = 'لسه ماظبطتش الاتصال';
      body = 'افتح الإعدادات وحط عنوان الـ Hub المحلي، أو بيانات السيرفر عشان تتحكم من برا البيت.';
    } else if (s.mode == ConnMode.offline) {
      title = 'مش لاقي الـ Hub';
      body = st.hasCloud
          ? 'اتأكد إن الـ ESP32 شغالة ومتصلة بالنت، وإن باسورد السيرفر صح.'
          : 'اتأكد إنك على نفس شبكة الواي فاي، أو ضيف بيانات السيرفر من الإعدادات.';
    } else if (s.query.isNotEmpty) {
      title = 'مفيش نتايج';
      body = 'مفيش مشترك أو مخرج بالاسم ده.';
    } else {
      title = 'مفيش مشترك متصل بالـ Hub';
      body = 'استنى دقيقة بعد ما المشترك يشتغل، أو افصله من الكهربا ورجّعه.';
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: C.textSoft, height: 1.6)),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: widget.onOpenSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: C.accent,
              side: const BorderSide(color: C.tileOnBorder),
              minimumSize: const Size(0, 44),
            ),
            child: const Text('الإعدادات'),
          ),
        ],
      ),
    );
  }
}

/// Shared helper for rename dialogs.
Future<String?> askName(BuildContext context, String title, String current) {
  final ctrl = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: Text(title, style: const TextStyle(fontSize: 18)),
      content: TextField(controller: ctrl, autofocus: true, textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ')),
      ],
    ),
  );
}

String shortMac(Strip s) => s.mac.length >= 4 ? s.mac.substring(s.mac.length - 4) : s.mac;
