// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'ريستوفلو';

  @override
  String get posAppTitle => 'ريستوفلو - نقطة البيع';

  @override
  String get kdsAppTitle => 'ريستوفلو - شاشة المطبخ';

  @override
  String get dashboardAppTitle => 'ريستوفلو - لوحة التحكم';

  @override
  String get adminAppTitle => 'ريستوفلو - الإدارة';

  @override
  String get welcomeMessage => 'مرحبًا بك في ريستوفلو';

  @override
  String get localeEnglish => 'الإنجليزية';

  @override
  String get localeArabic => 'العربية';

  @override
  String get localeHebrew => 'العبرية';

  @override
  String get kdsEmptyState => 'لا توجد تذاكر نشطة';

  @override
  String get kdsBumpAction => 'إنهاء';

  @override
  String get kdsRecallAction => 'استرجاع';

  @override
  String get kdsStationLabel => 'محطة';

  @override
  String get kdsTicketLabel => 'تذكرة';
}
