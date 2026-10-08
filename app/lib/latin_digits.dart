import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart' as intl_local;
import 'package:intl/intl.dart' as intl;

/// Arabic Material texts (pickers, dialogs) with every number in Western digits (0-9).
/// Listed before GlobalMaterialLocalizations.delegate, so it wins for 'ar'.
class LatinArMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const LatinArMaterialDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ar';

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    await intl_local.initializeDateFormatting('ar');
    intl.DateFormat.useNativeDigitsByDefaultFor('ar', false);
    return MaterialLocalizationAr(
      fullYearFormat: intl.DateFormat.y('ar'),
      compactDateFormat: intl.DateFormat.yMd('ar'),
      shortDateFormat: intl.DateFormat.yMMMd('ar'),
      mediumDateFormat: intl.DateFormat.MMMEd('ar'),
      longDateFormat: intl.DateFormat.yMMMMEEEEd('ar'),
      yearMonthFormat: intl.DateFormat.yMMMM('ar'),
      shortMonthDayFormat: intl.DateFormat.MMMd('ar'),
      decimalFormat: intl.NumberFormat('#,##0.###', 'en'),
      twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'en'),
    );
  }

  @override
  bool shouldReload(LatinArMaterialDelegate old) => false;
}
