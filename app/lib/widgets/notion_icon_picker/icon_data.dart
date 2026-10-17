part of '../notion_icon_picker.dart';

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
  // --- إضافات Phosphor (Phosphor extras) ---
  NotionIconItem(key: 'robot', icon: Icons.smart_toy_outlined, labelAr: 'أتمتة روبوت', labelEn: 'Automation', tags: ['robot', 'auto', 'أتمتة']),
  NotionIconItem(key: 'gauge', icon: Icons.speed_outlined, labelAr: 'عداد قياس', labelEn: 'Gauge', tags: ['meter', 'gauge', 'عداد']),
  NotionIconItem(key: 'hair_dryer', icon: Icons.air_outlined, labelAr: 'سشوار', labelEn: 'Hair dryer', tags: ['dryer', 'hair', 'سشوار']),
  NotionIconItem(key: 'toilet', icon: Icons.wc_outlined, labelAr: 'حمام تواليت', labelEn: 'Toilet', tags: ['wc', 'toilet', 'حمام']),
  NotionIconItem(key: 'lamp_pendant', icon: Icons.light_outlined, labelAr: 'نجفة معلقة', labelEn: 'Pendant lamp', tags: ['chandelier', 'lamp', 'نجفة']),
  NotionIconItem(key: 'projector', icon: Icons.videocam_outlined, labelAr: 'بروجيكتور', labelEn: 'Projector', tags: ['projector', 'cinema', 'بروجيكتور']),
  NotionIconItem(key: 'dog', icon: Icons.pets_outlined, labelAr: 'كلب', labelEn: 'Dog', tags: ['dog', 'pet', 'كلب']),
  NotionIconItem(key: 'cat', icon: Icons.pets_outlined, labelAr: 'قطة', labelEn: 'Cat', tags: ['cat', 'pet', 'قطة']),
  NotionIconItem(key: 'charging', icon: Icons.ev_station_outlined, labelAr: 'شاحن عربية', labelEn: 'EV charger', tags: ['ev', 'charger', 'شاحن', 'عربية']),
  NotionIconItem(key: 'plug_charging', icon: Icons.electrical_services_outlined, labelAr: 'فيشة بتشحن', labelEn: 'Charging plug', tags: ['charge', 'plug', 'شحن']),
  NotionIconItem(key: 'wind', icon: Icons.air_outlined, labelAr: 'هوا / شفاط', labelEn: 'Air / extractor', tags: ['air', 'fan', 'شفاط', 'هوا']),
  NotionIconItem(key: 'armchair', icon: Icons.chair_outlined, labelAr: 'فوتيه', labelEn: 'Armchair', tags: ['armchair', 'فوتيه']),
  NotionIconItem(key: 'food', icon: Icons.restaurant_outlined, labelAr: 'أكل', labelEn: 'Food', tags: ['food', 'meal', 'أكل']),
  // --- أجهزة كهربائية (appliances) ---
  NotionIconItem(key: 'coffee_machine', icon: Icons.coffee_maker_outlined, labelAr: 'ماكينة قهوة', labelEn: 'Coffee machine', tags: ['coffee', 'espresso', 'قهوة', 'اسبريسو']),
  NotionIconItem(key: 'coffee_grinder', icon: Icons.grain_outlined, labelAr: 'مطحنة قهوة', labelEn: 'Coffee grinder', tags: ['grinder', 'beans', 'مطحنة', 'بن']),
  NotionIconItem(key: 'water_heater', icon: Icons.hot_tub_outlined, labelAr: 'سخان مياه', labelEn: 'Water heater', tags: ['heater', 'boiler', 'سخان', 'مياه سخنة']),
  NotionIconItem(key: 'heater', icon: Icons.local_fire_department_outlined, labelAr: 'دفاية', labelEn: 'Heater', tags: ['heater', 'radiator', 'دفاية', 'تدفئة']),
  NotionIconItem(key: 'dishwasher', icon: Icons.countertops_outlined, labelAr: 'غسالة أطباق', labelEn: 'Dishwasher', tags: ['dishwasher', 'dishes', 'غسالة', 'أطباق', 'مواعين']),
  NotionIconItem(key: 'dryer', icon: Icons.dry_cleaning_outlined, labelAr: 'مجفف ملابس', labelEn: 'Clothes dryer', tags: ['dryer', 'laundry', 'مجفف', 'نشافة']),
  NotionIconItem(key: 'fridge', icon: Icons.kitchen_outlined, labelAr: 'تلاجة', labelEn: 'Fridge', tags: ['fridge', 'refrigerator', 'تلاجة', 'ثلاجة']),
  NotionIconItem(key: 'freezer', icon: Icons.severe_cold_outlined, labelAr: 'فريزر', labelEn: 'Freezer', tags: ['freezer', 'cold', 'فريزر', 'ديب فريزر']),
  NotionIconItem(key: 'blender', icon: Icons.blender_outlined, labelAr: 'خلاط', labelEn: 'Blender', tags: ['blender', 'mixer', 'خلاط', 'عصارة']),
  NotionIconItem(key: 'toaster', icon: Icons.breakfast_dining_outlined, labelAr: 'توستر', labelEn: 'Toaster', tags: ['toaster', 'bread', 'توستر', 'عيش']),
  NotionIconItem(key: 'food_warmer', icon: Icons.soup_kitchen_outlined, labelAr: 'سخان أكل / حلّة', labelEn: 'Food warmer / cooker', tags: ['cooker', 'rice', 'حلة', 'سخان أكل', 'رز']),
  NotionIconItem(key: 'popcorn', icon: Icons.movie_outlined, labelAr: 'ماكينة فشار', labelEn: 'Popcorn machine', tags: ['popcorn', 'فشار']),
  NotionIconItem(key: 'water_dispenser', icon: Icons.water_drop_outlined, labelAr: 'كولدير مياه', labelEn: 'Water dispenser', tags: ['water', 'cooler', 'كولدير', 'مياه']),
  NotionIconItem(key: 'water_pump', icon: Icons.plumbing_outlined, labelAr: 'موتور مياه', labelEn: 'Water pump', tags: ['pump', 'motor', 'موتور', 'طلمبة']),
  NotionIconItem(key: 'bulb_filament', icon: Icons.lightbulb_outline, labelAr: 'لمبة فتيل', labelEn: 'Filament bulb', tags: ['bulb', 'edison', 'لمبة', 'فتيل']),
  NotionIconItem(key: 'ceiling_light', icon: Icons.light_outlined, labelAr: 'لمبة سقف', labelEn: 'Ceiling light', tags: ['ceiling', 'light', 'سقف', 'لمبة']),
  NotionIconItem(key: 'spotlight', icon: Icons.highlight_outlined, labelAr: 'سبوت لايت', labelEn: 'Spotlight', tags: ['spot', 'spotlight', 'سبوت', 'إضاءة']),
  NotionIconItem(key: 'led_strip', icon: Icons.linear_scale_outlined, labelAr: 'شريط ليد', labelEn: 'LED strip', tags: ['led', 'strip', 'ليد', 'شريط']),
  NotionIconItem(key: 'party_lights', icon: Icons.celebration_outlined, labelAr: 'إضاءة حفلات', labelEn: 'Party lights', tags: ['disco', 'party', 'حفلة', 'ديسكو', 'إضاءة']),
  NotionIconItem(key: 'grow_light', icon: Icons.yard_outlined, labelAr: 'زرع / إضاءة زرع', labelEn: 'Plants / grow light', tags: ['plant', 'grow', 'زرع', 'نبات']),
  NotionIconItem(key: 'battery_charging', icon: Icons.battery_charging_full_outlined, labelAr: 'شاحن بطارية', labelEn: 'Battery charger', tags: ['charger', 'battery', 'شاحن', 'بطارية']),
  NotionIconItem(key: 'phone_charger', icon: Icons.charging_station_outlined, labelAr: 'شاحن موبايل', labelEn: 'Phone charger', tags: ['charger', 'phone', 'شاحن', 'موبايل']),
  NotionIconItem(key: 'car_battery', icon: Icons.car_repair_outlined, labelAr: 'بطارية عربية', labelEn: 'Car battery', tags: ['car', 'battery', 'عربية', 'بطارية']),
  NotionIconItem(key: 'speaker_hifi', icon: Icons.speaker_outlined, labelAr: 'سماعة كبيرة', labelEn: 'Hi-Fi speaker', tags: ['speaker', 'hifi', 'سماعة', 'ستريو']),
  NotionIconItem(key: 'soundbar', icon: Icons.surround_sound_outlined, labelAr: 'ساوند بار', labelEn: 'Soundbar', tags: ['soundbar', 'audio', 'ساوند', 'صوت']),
  NotionIconItem(key: 'pc_tower', icon: Icons.computer_outlined, labelAr: 'كمبيوتر (كيسة)', labelEn: 'PC tower', tags: ['pc', 'computer', 'كمبيوتر', 'كيسة']),
  NotionIconItem(key: 'hard_drive', icon: Icons.storage_outlined, labelAr: 'هارد / سيرفر', labelEn: 'Hard drive / server', tags: ['nas', 'server', 'هارد', 'سيرفر']),
  NotionIconItem(key: 'joystick', icon: Icons.sports_esports_outlined, labelAr: 'بلايستيشن / جويستك', labelEn: 'Console / joystick', tags: ['ps', 'playstation', 'xbox', 'بلايستيشن']),
  NotionIconItem(key: 'security_camera', icon: Icons.videocam_outlined, labelAr: 'كاميرا مراقبة', labelEn: 'Security camera', tags: ['camera', 'cctv', 'كاميرا', 'مراقبة']),
  NotionIconItem(key: 'vinyl', icon: Icons.album_outlined, labelAr: 'مشغل أسطوانات', labelEn: 'Record player', tags: ['vinyl', 'record', 'أسطوانات']),
  NotionIconItem(key: 'piano', icon: Icons.piano_outlined, labelAr: 'أورج', labelEn: 'Keyboard / piano', tags: ['piano', 'keyboard', 'أورج', 'بيانو']),
  NotionIconItem(key: 'guitar', icon: Icons.music_note_outlined, labelAr: 'جيتار / أمبلفاير', labelEn: 'Guitar / amp', tags: ['guitar', 'amp', 'جيتار']),
  NotionIconItem(key: 'aquarium', icon: Icons.set_meal_outlined, labelAr: 'حوض سمك', labelEn: 'Aquarium', tags: ['aquarium', 'fish', 'حوض', 'سمك']),
  NotionIconItem(key: 'siren', icon: Icons.notifications_active_outlined, labelAr: 'إنذار / جرس', labelEn: 'Alarm / siren', tags: ['alarm', 'siren', 'إنذار', 'سارينة']),
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
