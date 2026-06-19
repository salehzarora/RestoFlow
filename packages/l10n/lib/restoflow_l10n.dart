/// RestoFlow localization - shell only.
///
/// The FULL localization framework (ar/he/en ARB resources, message delegates,
/// and RTL/LTR scaffolding per DECISION D-014) is owned by ticket RF-020.
/// RF-011 declares only the neutral set of supported locales so other packages
/// can reference it without depending on the full framework.
library;

export 'src/supported_locales.dart';
