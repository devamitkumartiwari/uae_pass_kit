/// The display language for the UAE Pass hosted authentication and
/// signing UI, threaded through the documented `ui_locales` parameter.
enum UaePassLocale {
  /// English UI.
  en,

  /// Arabic UI.
  ar;

  /// The wire value sent as `ui_locales`.
  String get wireValue => name;
}
