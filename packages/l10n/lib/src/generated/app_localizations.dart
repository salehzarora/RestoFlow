import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('he'),
  ];

  /// The product name, shown across all surfaces.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow'**
  String get appName;

  /// Window/app title for the POS cashier app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow POS'**
  String get posAppTitle;

  /// Window/app title for the Kitchen Display System app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow KDS'**
  String get kdsAppTitle;

  /// Window/app title for the owner/manager dashboard app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow Dashboard'**
  String get dashboardAppTitle;

  /// Window/app title for the platform admin app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow Admin'**
  String get adminAppTitle;

  /// Generic welcome message shown on the scaffold body.
  ///
  /// In en, this message translates to:
  /// **'Welcome to RestoFlow'**
  String get welcomeMessage;

  /// Display name of the English locale.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get localeEnglish;

  /// Display name of the Arabic locale.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get localeArabic;

  /// Display name of the Hebrew locale.
  ///
  /// In en, this message translates to:
  /// **'Hebrew'**
  String get localeHebrew;

  /// KDS message shown when there are no tickets to display.
  ///
  /// In en, this message translates to:
  /// **'No active tickets'**
  String get kdsEmptyState;

  /// KDS action that marks a ready ticket as bumped (done).
  ///
  /// In en, this message translates to:
  /// **'Bump'**
  String get kdsBumpAction;

  /// KDS action that recalls a bumped ticket back into preparation.
  ///
  /// In en, this message translates to:
  /// **'Recall'**
  String get kdsRecallAction;

  /// KDS label prefixing a kitchen station name.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get kdsStationLabel;

  /// KDS label prefixing a kitchen ticket identifier.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get kdsTicketLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'he':
      return AppLocalizationsHe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
