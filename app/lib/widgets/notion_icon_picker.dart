import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../i18n.dart';

/// Single item in the Notion-style icon catalog.
class NotionIconItem {
  final String key;
  final IconData icon;
  final String labelAr;
  final String labelEn;
  final List<String> tags;

  const NotionIconItem({
    required this.key,
    required this.icon,
    required this.labelAr,
    required this.labelEn,
    this.tags = const [],
  });
}

/// Curated Notion-style monochrome outline icons.
const List<NotionIconItem> kNotionIcons = [
  // --- الأسهم والاتجاهات (Arrows) ---
  NotionIconItem(key: 'arrow_forward', icon: Icons.arrow_forward_outlined, labelAr: 'سهم لليمين', labelEn: 'Arrow forward', tags: ['right', 'يمين', 'سهم']),
  NotionIconItem(key: 'arrow_back', icon: Icons.arrow_back_outlined, labelAr: 'سهم لليسار', labelEn: 'Arrow back', tags: ['left', 'يسار', 'سهم']),
  NotionIconItem(key: 'arrow_up', icon: Icons.arrow_upward_outlined, labelAr: 'سهم لأعلى', labelEn: 'Arrow up', tags: ['up', 'فوق', 'سهم']),
  NotionIconItem(key: 'arrow_down', icon: Icons.arrow_downward_outlined, labelAr: 'سهم لأسفل', labelEn: 'Arrow down', tags: ['down', 'تحت', 'سهم']),
  NotionIconItem(key: 'swap_horiz', icon: Icons.swap_horiz_outlined, labelAr: 'تبديل أفقي', labelEn: 'Swap horizontal', tags: ['switch', 'تبديل']),
  NotionIconItem(key: 'swap_vert', icon: Icons.swap_vert_outlined, labelAr: 'تبديل رأسي', labelEn: 'Swap vertical', tags: ['vertical', 'رأسي']),
  NotionIconItem(key: 'sync', icon: Icons.sync_outlined, labelAr: 'مزامنة', labelEn: 'Sync', tags: ['sync', 'refresh', 'مزامنة', 'تحديث']),
  NotionIconItem(key: 'restart', icon: Icons.restart_alt_outlined, labelAr: 'إعادة تشغيل', labelEn: 'Restart', tags: ['reboot', 'restart', 'ريستارت']),

  // --- أجهزة كهربائية وإلكترونيات (Devices & Tech) ---
  NotionIconItem(key: 'tv', icon: Icons.tv_outlined, labelAr: 'تلفزيون', labelEn: 'TV', tags: ['tv', 'screen', 'تلفزيون', 'شاشة']),
  NotionIconItem(key: 'desktop', icon: Icons.desktop_windows_outlined, labelAr: 'كمبيوتر مكتبي', labelEn: 'Desktop PC', tags: ['pc', 'computer', 'كمبيوتر']),
  NotionIconItem(key: 'laptop', icon: Icons.laptop_outlined, labelAr: 'لابتوب', labelEn: 'Laptop', tags: ['laptop', 'notebook', 'لابتوب']),
  NotionIconItem(key: 'monitor', icon: Icons.monitor_outlined, labelAr: 'شاشة', labelEn: 'Monitor', tags: ['screen', 'monitor', 'شاشة']),
  NotionIconItem(key: 'phone', icon: Icons.smartphone_outlined, labelAr: 'موبايل', labelEn: 'Smartphone', tags: ['phone', 'mobile', 'موبايل', 'هاتف']),
  NotionIconItem(key: 'tablet', icon: Icons.tablet_android_outlined, labelAr: 'تابلت', labelEn: 'Tablet', tags: ['tablet', 'ipad', 'تابلت']),
  NotionIconItem(key: 'router', icon: Icons.router_outlined, labelAr: 'راوتر وواي فاي', labelEn: 'Router', tags: ['wifi', 'router', 'internet', 'راوتر', 'نت']),
  NotionIconItem(key: 'wifi', icon: Icons.wifi_outlined, labelAr: 'شبكة واي فاي', labelEn: 'Wi-Fi', tags: ['wifi', 'wireless', 'شبكة']),
  NotionIconItem(key: 'speaker', icon: Icons.speaker_outlined, labelAr: 'سماعة سبيكر', labelEn: 'Speaker', tags: ['sound', 'audio', 'سماعة']),
  NotionIconItem(key: 'headphones', icon: Icons.headphones_outlined, labelAr: 'سماعات رأس', labelEn: 'Headphones', tags: ['headset', 'headphones', 'هيدفون']),
  NotionIconItem(key: 'mic', icon: Icons.mic_none_outlined, labelAr: 'مايكروفون', labelEn: 'Microphone', tags: ['mic', 'audio', 'مايك']),
  NotionIconItem(key: 'camera', icon: Icons.videocam_outlined, labelAr: 'كاميرا مراقبة', labelEn: 'Camera', tags: ['cctv', 'cam', 'كاميرا']),
  NotionIconItem(key: 'photo', icon: Icons.camera_alt_outlined, labelAr: 'كاميرا فوتو', labelEn: 'Photo camera', tags: ['photo', 'تصوير']),
  NotionIconItem(key: 'printer', icon: Icons.print_outlined, labelAr: 'طابعة', labelEn: 'Printer', tags: ['print', 'printer', 'طابعة']),
  NotionIconItem(key: 'gamepad', icon: Icons.sports_esports_outlined, labelAr: 'ألعاب وبلايستيشن', labelEn: 'Gaming console', tags: ['ps5', 'game', 'playstation', 'ألعاب']),
  NotionIconItem(key: 'watch', icon: Icons.watch_outlined, labelAr: 'ساعة ذكية', labelEn: 'Smartwatch', tags: ['watch', 'clock', 'ساعة']),
  NotionIconItem(key: 'mouse', icon: Icons.mouse_outlined, labelAr: 'ماوس', labelEn: 'Mouse', tags: ['mouse', 'ماوس']),
  NotionIconItem(key: 'keyboard', icon: Icons.keyboard_outlined, labelAr: 'لوحة مفاتيح', labelEn: 'Keyboard', tags: ['keyboard', 'كيبورد']),
  NotionIconItem(key: 'radio', icon: Icons.radio_outlined, labelAr: 'راديو', labelEn: 'Radio', tags: ['radio', 'راديو']),
  NotionIconItem(key: 'memory', icon: Icons.memory_outlined, labelAr: 'معالج شريحة', labelEn: 'Chip', tags: ['chip', 'cpu', 'بروسيسور']),

  // --- طاقة وكهرباء (Power & Energy) ---
  NotionIconItem(key: 'power', icon: Icons.power_outlined, labelAr: 'فيشة كهرباء', labelEn: 'Power plug', tags: ['plug', 'power', 'فيشة', 'مقبس']),
  NotionIconItem(key: 'bolt', icon: Icons.bolt_outlined, labelAr: 'برق وطاقة', labelEn: 'Lightning bolt', tags: ['energy', 'bolt', 'كهرباء', 'طاقة']),
  NotionIconItem(key: 'outlet', icon: Icons.electrical_services_outlined, labelAr: 'مخرج كهرباء', labelEn: 'Outlet', tags: ['socket', 'outlet', 'مخرج', 'مشترك']),
  NotionIconItem(key: 'switch', icon: Icons.power_settings_new_outlined, labelAr: 'مفتاح تشغيل', labelEn: 'Power switch', tags: ['switch', 'on', 'off', 'مفتاح', 'زرار']),
  NotionIconItem(key: 'cable', icon: Icons.cable_outlined, labelAr: 'كابل سلك', labelEn: 'Cable', tags: ['wire', 'cable', 'سلك', 'وصلة']),
  NotionIconItem(key: 'lightbulb', icon: Icons.lightbulb_outline, labelAr: 'لمبة إضاءة', labelEn: 'Light bulb', tags: ['lamp', 'bulb', 'لمبة', 'نور', 'إضاءة']),
  NotionIconItem(key: 'lamp', icon: Icons.tungsten_outlined, labelAr: 'أباجورة مكتب', labelEn: 'Desk lamp', tags: ['lamp', 'desk', 'مصباح', 'أباجورة']),
  NotionIconItem(key: 'flashlight', icon: Icons.flashlight_on_outlined, labelAr: 'كشاف يدوي', labelEn: 'Flashlight', tags: ['torch', 'كشاف']),
  NotionIconItem(key: 'battery_full', icon: Icons.battery_charging_full_outlined, labelAr: 'شاحن بطارية', labelEn: 'Battery charging', tags: ['battery', 'charger', 'شاحن', 'بطارية']),
  NotionIconItem(key: 'battery', icon: Icons.battery_std_outlined, labelAr: 'بطارية', labelEn: 'Battery', tags: ['battery', 'بطارية']),
  NotionIconItem(key: 'solar', icon: Icons.solar_power_outlined, labelAr: 'طاقة شمسية', labelEn: 'Solar power', tags: ['solar', 'energy', 'شمسية']),
  NotionIconItem(key: 'eco', icon: Icons.eco_outlined, labelAr: 'توفير طاقة', labelEn: 'Eco friendly', tags: ['eco', 'green', 'بيئة', 'توفير']),

  // --- أجهزة منزلية ومطبخ (Appliances & Kitchen) ---
  NotionIconItem(key: 'ac', icon: Icons.ac_unit_outlined, labelAr: 'تكييف تبريد', labelEn: 'Air conditioner', tags: ['ac', 'cooler', 'مكيف', 'تكييف', 'تبريد']),
  NotionIconItem(key: 'fan', icon: Icons.mode_fan_off_outlined, labelAr: 'مروحة', labelEn: 'Fan', tags: ['fan', 'air', 'مروحة', 'تهوية']),
  NotionIconItem(key: 'fridge', icon: Icons.kitchen_outlined, labelAr: 'ثلاجة', labelEn: 'Refrigerator', tags: ['fridge', 'kitchen', 'ثلاجة', 'تلاجة']),
  NotionIconItem(key: 'microwave', icon: Icons.microwave_outlined, labelAr: 'ميكروويف أو فرن', labelEn: 'Microwave', tags: ['oven', 'microwave', 'فرن', 'ميكروويف']),
  NotionIconItem(key: 'coffee', icon: Icons.coffee_maker_outlined, labelAr: 'ماكينة قهوة', labelEn: 'Coffee maker', tags: ['coffee', 'espresso', 'قهوة']),
  NotionIconItem(key: 'cafe', icon: Icons.local_cafe_outlined, labelAr: 'كوب شاي أو قهوة', labelEn: 'Hot beverage', tags: ['tea', 'cup', 'شاي', 'نسكافيه']),
  NotionIconItem(key: 'kettle', icon: Icons.soup_kitchen_outlined, labelAr: 'غلاية كاتيل', labelEn: 'Kettle / Cooking', tags: ['kettle', 'cooking', 'كاتيل', 'غلاية']),
  NotionIconItem(key: 'washer', icon: Icons.local_laundry_service_outlined, labelAr: 'غسالة ملابس', labelEn: 'Washing machine', tags: ['washer', 'laundry', 'غسالة']),
  NotionIconItem(key: 'iron', icon: Icons.iron_outlined, labelAr: 'مكواة', labelEn: 'Iron', tags: ['iron', 'مكواة']),
  NotionIconItem(key: 'cleaning', icon: Icons.cleaning_services_outlined, labelAr: 'مكنسة تنظيف', labelEn: 'Vacuum / Cleaning', tags: ['vacuum', 'clean', 'مكنسة', 'تنظيف']),
  NotionIconItem(key: 'water', icon: Icons.water_drop_outlined, labelAr: 'سخان ماء / فلتر', labelEn: 'Water heater / drop', tags: ['heater', 'water', 'سخان', 'مياه']),
  NotionIconItem(key: 'fire', icon: Icons.local_fire_department_outlined, labelAr: 'دفاية أو سخان', labelEn: 'Heater / Flame', tags: ['heater', 'fire', 'دفاية', 'حرارة']),

  // --- غرف وأثاث (Rooms & Furniture) ---
  NotionIconItem(key: 'home', icon: Icons.home_outlined, labelAr: 'المنزل', labelEn: 'Home', tags: ['house', 'home', 'منزل', 'بيت']),
  NotionIconItem(key: 'room', icon: Icons.meeting_room_outlined, labelAr: 'غرفة', labelEn: 'Room', tags: ['room', 'door', 'غرفة']),
  NotionIconItem(key: 'sofa', icon: Icons.weekend_outlined, labelAr: 'صالون / معيشة', labelEn: 'Living room', tags: ['sofa', 'salon', 'كنبة', 'صالون', 'صالة']),
  NotionIconItem(key: 'bed', icon: Icons.bed_outlined, labelAr: 'غرفة نوم / سرير', labelEn: 'Bedroom', tags: ['bed', 'sleep', 'سرير', 'نوم']),
  NotionIconItem(key: 'desk', icon: Icons.desk_outlined, labelAr: 'مكتب عمل', labelEn: 'Work desk', tags: ['office', 'desk', 'مكتب']),
  NotionIconItem(key: 'chair', icon: Icons.chair_outlined, labelAr: 'كرسي', labelEn: 'Chair', tags: ['seat', 'chair', 'كرسي']),
  NotionIconItem(key: 'bath', icon: Icons.bathtub_outlined, labelAr: 'حمام / بانيو', labelEn: 'Bathroom', tags: ['bath', 'toilet', 'حمام']),
  NotionIconItem(key: 'shower', icon: Icons.shower_outlined, labelAr: 'دش حمام', labelEn: 'Shower', tags: ['shower', 'دش']),
  NotionIconItem(key: 'yard', icon: Icons.yard_outlined, labelAr: 'حديقة / فناء', labelEn: 'Garden / Yard', tags: ['garden', 'yard', 'حديقة']),
  NotionIconItem(key: 'garage', icon: Icons.garage_outlined, labelAr: 'جراج', labelEn: 'Garage', tags: ['garage', 'car', 'جراج']),
  NotionIconItem(key: 'balcony', icon: Icons.balcony_outlined, labelAr: 'بلكونة', labelEn: 'Balcony', tags: ['balcony', 'بلكونة']),
  NotionIconItem(key: 'door', icon: Icons.sensor_door_outlined, labelAr: 'باب', labelEn: 'Door', tags: ['door', 'باب']),
  NotionIconItem(key: 'window', icon: Icons.window_outlined, labelAr: 'شباك', labelEn: 'Window', tags: ['window', 'شباك']),
  NotionIconItem(key: 'building', icon: Icons.apartment_outlined, labelAr: 'مبنى / عمارة', labelEn: 'Building', tags: ['building', 'office', 'عمارة']),

  // --- رموز وأمان وإشعارات (Symbols & Utility) ---
  NotionIconItem(key: 'shield', icon: Icons.shield_outlined, labelAr: 'حماية وأمان', labelEn: 'Security shield', tags: ['shield', 'safe', 'حماية', 'أمان']),
  NotionIconItem(key: 'lock', icon: Icons.lock_outline, labelAr: 'قفل أمان', labelEn: 'Lock', tags: ['lock', 'child', 'قفل']),
  NotionIconItem(key: 'unlock', icon: Icons.lock_open_outlined, labelAr: 'مفتوح', labelEn: 'Unlock', tags: ['open', 'unlock', 'فتح']),
  NotionIconItem(key: 'clock', icon: Icons.access_time_outlined, labelAr: 'ساعة وتوقيت', labelEn: 'Clock', tags: ['time', 'clock', 'ساعة', 'وقت']),
  NotionIconItem(key: 'timer', icon: Icons.timer_outlined, labelAr: 'مؤقت تايمر', labelEn: 'Timer', tags: ['timer', 'countdown', 'تايمر', 'مؤقت']),
  NotionIconItem(key: 'calendar', icon: Icons.calendar_today_outlined, labelAr: 'تقويم وجدولة', labelEn: 'Schedule / Calendar', tags: ['schedule', 'calendar', 'جدولة']),
  NotionIconItem(key: 'bell', icon: Icons.notifications_none_outlined, labelAr: 'تنبيه جرس', labelEn: 'Notification bell', tags: ['bell', 'alert', 'جرس', 'إشعار']),
  NotionIconItem(key: 'bell_off', icon: Icons.notifications_off_outlined, labelAr: 'كتم التنبيه', labelEn: 'Mute bell', tags: ['mute', 'silent', 'كتم']),
  NotionIconItem(key: 'bookmark', icon: Icons.bookmark_border_outlined, labelAr: 'إشارة مرجعية', labelEn: 'Bookmark', tags: ['bookmark', 'save', 'حفظ']),
  NotionIconItem(key: 'star', icon: Icons.star_border_outlined, labelAr: 'نجمة مفضلة', labelEn: 'Star', tags: ['favorite', 'star', 'مفضل', 'نجمة']),
  NotionIconItem(key: 'heart', icon: Icons.favorite_border_outlined, labelAr: 'قلب مفضل', labelEn: 'Heart', tags: ['heart', 'love', 'قلب']),
  NotionIconItem(key: 'pin', icon: Icons.push_pin_outlined, labelAr: 'دبوس تثبيت', labelEn: 'Pin', tags: ['pin', 'keep', 'تثبيت', 'دبوس']),
  NotionIconItem(key: 'tag', icon: Icons.label_outline, labelAr: 'علامة تصنيف', labelEn: 'Tag', tags: ['tag', 'label', 'علامة']),
  NotionIconItem(key: 'folder', icon: Icons.folder_open_outlined, labelAr: 'مجلد', labelEn: 'Folder', tags: ['folder', 'مجلد']),
  NotionIconItem(key: 'box', icon: Icons.inventory_2_outlined, labelAr: 'صندوق كرتونة', labelEn: 'Package box', tags: ['box', 'package', 'صندوق']),
  NotionIconItem(key: 'link', icon: Icons.link_outlined, labelAr: 'رابط وصلة', labelEn: 'Link', tags: ['link', 'chain', 'رابط']),
  NotionIconItem(key: 'sparkle', icon: Icons.auto_awesome_outlined, labelAr: 'ذكاء وسحر', labelEn: 'Sparkles', tags: ['ai', 'magic', 'sparkle', 'سيناريو']),
  NotionIconItem(key: 'tune', icon: Icons.tune_outlined, labelAr: 'إعدادات تحكم', labelEn: 'Adjust tune', tags: ['tune', 'settings', 'إعدادات']),
  NotionIconItem(key: 'wrench', icon: Icons.build_outlined, labelAr: 'أدوات وصيانة', labelEn: 'Tools', tags: ['tools', 'wrench', 'صيانة', 'مفك']),
  NotionIconItem(key: 'check', icon: Icons.check_circle_outline, labelAr: 'صح مكتمل', labelEn: 'Check mark', tags: ['check', 'done', 'صح', 'تم']),
  NotionIconItem(key: 'warning', icon: Icons.warning_amber_outlined, labelAr: 'تحذير خطر', labelEn: 'Warning', tags: ['warn', 'danger', 'تحذير']),

  // --- عام ومنوعات (Misc & Life) ---
  NotionIconItem(key: 'sun', icon: Icons.wb_sunny_outlined, labelAr: 'شمس نهار', labelEn: 'Sun', tags: ['sun', 'day', 'شمس', 'نهار']),
  NotionIconItem(key: 'moon', icon: Icons.nightlight_round_outlined, labelAr: 'هلال ليل', labelEn: 'Moon night', tags: ['moon', 'night', 'قمر', 'ليل']),
  NotionIconItem(key: 'thermostat', icon: Icons.thermostat_outlined, labelAr: 'حرارة ترمومتر', labelEn: 'Thermostat', tags: ['temp', 'heat', 'حرارة']),
  NotionIconItem(key: 'car', icon: Icons.directions_car_outlined, labelAr: 'سيارة عربية', labelEn: 'Car', tags: ['car', 'auto', 'سيارة', 'عربية']),
  NotionIconItem(key: 'bike', icon: Icons.directions_bike_outlined, labelAr: 'دراجة عجلة', labelEn: 'Bicycle', tags: ['bike', 'دراجة', 'عجلة']),
  NotionIconItem(key: 'plane', icon: Icons.flight_outlined, labelAr: 'طائرة سفر', labelEn: 'Airplane', tags: ['plane', 'flight', 'طيارة', 'سفر']),
  NotionIconItem(key: 'boat', icon: Icons.directions_boat_outlined, labelAr: 'قارب بحر', labelEn: 'Boat', tags: ['boat', 'ship', 'مركب']),
  NotionIconItem(key: 'pet', icon: Icons.pets_outlined, labelAr: 'حيوان أليف', labelEn: 'Pet', tags: ['cat', 'dog', 'pet', 'قطة', 'كلب']),
  NotionIconItem(key: 'baby', icon: Icons.child_care_outlined, labelAr: 'طفل بيبي', labelEn: 'Baby', tags: ['baby', 'kid', 'طفل', 'بيبي']),
  NotionIconItem(key: 'tree', icon: Icons.park_outlined, labelAr: 'شجرة نبات', labelEn: 'Tree', tags: ['tree', 'nature', 'شجرة']),
  NotionIconItem(key: 'flower', icon: Icons.local_florist_outlined, labelAr: 'وردة زهرة', labelEn: 'Flower', tags: ['flower', 'rose', 'وردة']),
  NotionIconItem(key: 'music', icon: Icons.music_note_outlined, labelAr: 'نغمة موسيقى', labelEn: 'Music note', tags: ['music', 'song', 'موسيقى']),
  NotionIconItem(key: 'book', icon: Icons.menu_book_outlined, labelAr: 'كتاب قراءة', labelEn: 'Book', tags: ['book', 'read', 'كتاب']),
  NotionIconItem(key: 'fitness', icon: Icons.fitness_center_outlined, labelAr: 'جيم ورياضة', labelEn: 'Fitness / Gym', tags: ['gym', 'fitness', 'رياضة', 'جيم']),
  NotionIconItem(key: 'gift', icon: Icons.card_giftcard_outlined, labelAr: 'هدية', labelEn: 'Gift', tags: ['gift', 'present', 'هدية']),
  NotionIconItem(key: 'cake', icon: Icons.cake_outlined, labelAr: 'تورتة احتفال', labelEn: 'Cake', tags: ['cake', 'birthday', 'تورتة', 'عيد']),
];

/// Map of key -> IconData for instant lookup.
final Map<String, IconData> kNotionIconMap = {
  for (final item in kNotionIcons) item.key: item.icon,
};

/// Curated emojis grouped for smart home and everyday setups.
const List<String> kCuratedEmojis = [
  // أجهزة ومخارج وكهرباء
  '⚡', '🔌', '💡', '🔦', '🔋', '⏰', '🔒', '📶', '🖲️', '🎛️',
  // أجهزة مكتب وتكنولوجيا وترفيه
  '💻', '🖥️', '🖨️', '📱', '📺', '🎮', '🕹️', '🔊', '🎧', '📷',
  // مطبخ وتبريد وتسخين
  '❄️', '🔥', '☕', '🍳', '🍽️', '🧊', '🫖', '🥘', '🍲', '🧂',
  // غرف وأثاث ومنزل
  '🏠', '🛋️', '🛏️', '🪑', '🚪', '🚿', '🧺', '🪴', '🧸', '👶',
  // رموز وعلامات وملاحة
  '⭐', '❤️', '📍', '📌', '🔔', '🔕', '🛡️', '🏷️', '📦', '🎯',
  '☀️', '🌙', '💧', '🚗', '🚲', '✈️', '🌱', '🎵', '📚', '🏋️',
];

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
      final key = icon.substring(5);
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
      widget.onSelected('icon:${picked.key}');
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
          final isSelected = widget.currentIcon == 'icon:${item.key}';

          return Tooltip(
            message: Tr.isAr ? item.labelAr : item.labelEn,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                widget.onSelected('icon:${item.key}');
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
                child: Icon(
                  item.icon,
                  size: 20,
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
