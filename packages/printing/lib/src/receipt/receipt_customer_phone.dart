/// Displays a recognized Israeli international customer number in its local
/// form on a receipt. This does not validate input for storage, change an order,
/// choose a country for other numbers, or build a dialing URI.
///
/// Existing local display strings and unrecognized/international values retain
/// their exact spelling. Formatting is deliberately limited to +972 mobile
/// (05x), geographic (02/03/04/08/09) and national/VoIP (07) format families.
/// These are format checks, not proof that a subscriber number is allocated.
String formatReceiptCustomerPhone(String value) {
  if (RegExp(r'[^+0-9 ()-]').hasMatch(value)) return value;
  final compact = value.replaceAll(RegExp(r'[ ()-]'), '');
  if (RegExp(
    r'^\+972(?:5[0-9]{8}|[23489][2-9][0-9]{6}|7[2-9][2-9][0-9]{6})$',
  ).hasMatch(compact)) {
    return '0${compact.substring(4)}';
  }
  return value;
}
