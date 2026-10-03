/// Same API as the parts of package:home_widget Fisha uses, talking to MainActivity over a MethodChannel.
library;

import 'package:flutter/services.dart';

class HomeWidget {
  static const _channel = MethodChannel('fisha/widget');
  static final Map<String, String> _data = {};

  static Future<bool?> saveWidgetData<T>(String id, T? data) async {
    _data[id] = data?.toString() ?? '';
    return true;
  }

  static Future<bool?> updateWidget({String? name, String? androidName, String? iOSName, String? qualifiedAndroidName}) async {
    try {
      return await _channel.invokeMethod<bool>('update', Map<String, String>.from(_data));
    } catch (_) {
      return false;
    }
  }
}
