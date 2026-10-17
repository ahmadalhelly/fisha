import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../i18n.dart';
import 'phosphor_catalog.dart';

part 'notion_icon_picker/icon_data.dart';

/// Universal icon widget that renders either a Notion outline icon (`icon:<key>`) or an emoji string.
class FishaIcon extends StatelessWidget {
  final String icon;
  final double size;
  final Color? color;
  final IconData? defaultIcon;

  const FishaIcon({
    super.key,
    required this.icon,
    this.size = 20,
    this.color,
    this.defaultIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (icon.startsWith('icon:')) {
      // 'icon:<key>' = Phosphor duotone, 'icon:<key>@light' = Phosphor light; keys Phosphor lacks stay Material
      final light = icon.endsWith('@light');
      final key = icon.substring(5, light ? icon.length - 6 : icon.length);
      final ph = kPhosphorIcons[key];
      if (ph != null) {
        final c = color ?? C.textSoft;
        if (light) return Icon(ph.light, size: size, color: c);
        return Stack(alignment: Alignment.center, children: [
          Icon(ph.duoFill, size: size, color: c.withValues(alpha: 0.28)),
          Icon(ph.duo, size: size, color: c),
        ]);
      }
      final data = kNotionIconMap[key] ?? defaultIcon ?? Icons.category_outlined;
      return Icon(data, size: size, color: color ?? C.textSoft);
    }
    if (icon.isNotEmpty) {
      return Text(
        icon,
        style: TextStyle(fontSize: size, height: 1.1),
      );
    }
    if (defaultIcon != null) {
      return Icon(defaultIcon, size: size, color: color ?? C.textSoft);
    }
    return const SizedBox.shrink();
  }
}

/// Notion-style Icon & Emoji Picker Dialog.
Future<void> showNotionIconPicker({
  required BuildContext context,
  required String currentIcon,
  required ValueChanged<String> onSelected,
  String? title,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _NotionIconPickerDialog(
      currentIcon: currentIcon,
      onSelected: onSelected,
      title: title,
    ),
  );
}

class _NotionIconPickerDialog extends StatefulWidget {
  final String currentIcon;
  final ValueChanged<String> onSelected;
  final String? title;

  const _NotionIconPickerDialog({
    required this.currentIcon,
    required this.onSelected,
    this.title,
  });

  @override
  State<_NotionIconPickerDialog> createState() => _NotionIconPickerDialogState();
}

class _NotionIconPickerDialogState extends State<_NotionIconPickerDialog> {
  int _activeTab = 0; // 0 = Icon, 1 = Emoji
  late bool _light = widget.currentIcon.endsWith('@light'); // Phosphor style: light, or duotone (default)
  String _iconValue(String key) => 'icon:$key${_light ? '@light' : ''}';
  String get _currentKey {
    final c = widget.currentIcon;
    if (!c.startsWith('icon:')) return '';
    return c.endsWith('@light') ? c.substring(5, c.length - 6) : c.substring(5);
  }
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _emojiPasteCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // If current icon is an emoji, default to the Emoji tab
    if (widget.currentIcon.isNotEmpty && !widget.currentIcon.startsWith('icon:')) {
      _activeTab = 1;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _emojiPasteCtrl.dispose();
    super.dispose();
  }

  List<NotionIconItem> get _filteredIcons {
    if (_searchQuery.trim().isEmpty) return kNotionIcons;
    final q = _searchQuery.trim().toLowerCase();
    return kNotionIcons.where((item) {
      if (item.key.toLowerCase().contains(q)) return true;
      if (item.labelAr.toLowerCase().contains(q)) return true;
      if (item.labelEn.toLowerCase().contains(q)) return true;
      for (final tag in item.tags) {
        if (tag.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  void _shuffle() {
    final rand = math.Random();
    if (_activeTab == 0) {
      final icons = _filteredIcons.isNotEmpty ? _filteredIcons : kNotionIcons;
      final picked = icons[rand.nextInt(icons.length)];
      widget.onSelected(_iconValue(picked.key));
      Navigator.pop(context);
    } else {
      final picked = kCuratedEmojis[rand.nextInt(kCuratedEmojis.length)];
      widget.onSelected(picked);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Tr.isAr;
    final filtered = _filteredIcons;

    return Dialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: C.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar: Tab Switcher (Icon / Emoji) + Remove button
              Row(
                children: [
                  // Notion-style Segmented Tab selector
                  Container(
                    decoration: BoxDecoration(
                      color: C.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: C.border),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _tabButton(0, isAr ? 'الأيقونات' : 'Icon', Icons.interests_outlined),
                        _tabButton(1, isAr ? 'الإيموجي' : 'Emoji', Icons.emoji_emotions_outlined),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Remove button
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: C.muted,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(isAr ? 'حذف' : 'Remove', style: const TextStyle(fontSize: 12.5)),
                    onPressed: () {
                      widget.onSelected('');
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar + Shuffle button (faithful to Notion UI)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: C.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: C.border),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: TextStyle(fontSize: 13, color: C.text),
                        decoration: InputDecoration(
                          hintText: isAr ? 'ابحث عن أيقونة...' : 'Filter...',
                          hintStyle: TextStyle(fontSize: 13, color: C.muted),
                          prefixIcon: Icon(Icons.search, size: 18, color: C.muted),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  color: C.muted,
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Shuffle / Random Button
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: C.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: C.border),
                    ),
                    child: IconButton(
                      tooltip: isAr ? 'اختيار عشوائي' : 'Random icon',
                      icon: Icon(Icons.shuffle, size: 18, color: C.textSoft),
                      onPressed: _shuffle,
                    ),
                  ),
                ],
              ),
              if (_activeTab == 0) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Text(isAr ? 'الستايل' : 'Style', style: TextStyle(fontSize: 12, color: C.muted)),
                  const SizedBox(width: 8),
                  _styleChip(false, 'Duotone'),
                  const SizedBox(width: 6),
                  _styleChip(true, 'Light'),
                ]),
              ],
              const SizedBox(height: 12),

              // Body content
              Expanded(
                child: _activeTab == 0
                    ? _buildIconGrid(filtered)
                    : _buildEmojiView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _styleChip(bool light, String label) {
    final active = _light == light;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _light = light),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? C.text : C.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? C.text : C.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? C.bg : C.textSoft)),
      ),
    );
  }

  Widget _tabButton(int index, String label, IconData icon) {
    final active = _activeTab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? C.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active ? Border.all(color: C.accent.withValues(alpha: 0.35)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? C.accent : C.muted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? C.accent : C.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconGrid(List<NotionIconItem> icons) {
    if (icons.isEmpty) {
      return Center(
        child: Text(
          Tr.isAr ? 'لا توجد أيقونات مطابقة' : 'No matching icons',
          style: TextStyle(color: C.muted, fontSize: 13),
        ),
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      child: GridView.builder(
        padding: const EdgeInsets.only(right: 6, bottom: 4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.0,
        ),
        itemCount: icons.length,
        itemBuilder: (ctx, i) {
          final item = icons[i];
          final isSelected = _currentKey == item.key;

          return Tooltip(
            message: Tr.isAr ? item.labelAr : item.labelEn,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                widget.onSelected(_iconValue(item.key));
                Navigator.pop(context);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? C.accent.withValues(alpha: 0.15) : C.surface2.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? C.accent : C.border,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: FishaIcon(
                  icon: _iconValue(item.key),
                  size: 22,
                  color: isSelected ? C.accent : C.textSoft,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmojiView() {
    final isAr = Tr.isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Custom emoji paste row
        Row(
          children: [
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: C.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: C.border),
                ),
                child: TextField(
                  controller: _emojiPasteCtrl,
                  style: TextStyle(fontSize: 13, color: C.text),
                  decoration: InputDecoration(
                    hintText: isAr ? 'أو الصق إيموجي هنا...' : 'Paste custom emoji...',
                    hintStyle: TextStyle(fontSize: 12, color: C.muted),
                    prefixIcon: Icon(Icons.paste_outlined, size: 16, color: C.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: C.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final val = _emojiPasteCtrl.text.trim();
                final hasLetters = RegExp(r'[a-zA-Z\u0600-\u06FF0-9]').hasMatch(val);
                if (hasLetters) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isAr ? 'ممنوع كتابة حروف أو كلمات، استخدم إيموجي فقط' : 'Use emoji characters only')),
                  );
                  return;
                }
                if (val.isNotEmpty) {
                  widget.onSelected(val);
                  Navigator.pop(context);
                }
              },
              child: Text(isAr ? 'تطبيق' : 'Apply', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Emoji Grid
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: GridView.builder(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: kCuratedEmojis.length,
              itemBuilder: (ctx, i) {
                final em = kCuratedEmojis[i];
                final isSelected = widget.currentIcon == em;

                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    widget.onSelected(em);
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? C.accent.withValues(alpha: 0.15) : C.surface2.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? C.accent : C.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(em, style: const TextStyle(fontSize: 20)),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
