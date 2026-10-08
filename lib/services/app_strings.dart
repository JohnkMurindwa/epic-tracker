import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns [en] or [es] depending on the current app language.
/// Use for any user-facing text: `Text(tr('Clock Out', 'Registrar Salida'))`.
String tr(String en, String es) => AppStrings.isSpanish ? es : en;

/// Bilingual (English / Spanish) string support for the whole app.
///
/// The language is a per-user preference: the app starts in English, and
/// after sign-in switches to the language that user last chose. The choice
/// is saved on the user's Firestore document (`language` field) and also
/// on this device under the user's id, as a fallback if the Firestore
/// write is not permitted. Signing out returns the app to English.
///
/// Screens call [AppStrings.watch] at the top of `build` so they rebuild
/// when the language changes.
class AppStrings {
  static final ValueNotifier<String> localeNotifier = ValueNotifier('en');

  /// The signed-in user whose preference is being saved, if any.
  static String? _userId;

  static String get locale => localeNotifier.value;
  static bool get isSpanish => locale == 'es';

  /// Locale name for `DateFormat(pattern, AppStrings.dateLocale)`.
  static String get dateLocale => isSpanish ? 'es' : 'en_US';

  static String _prefsKey(String userId) => 'app_locale_$userId';

  /// Applies [userId]'s saved language after sign-in.
  ///
  /// [savedLanguage] is the `language` field from their Firestore document.
  /// If they switched to Spanish on the login screen just now, that choice
  /// wins and is saved as their preference.
  static Future<void> onSignIn(String userId, String? savedLanguage) async {
    _userId = userId;
    if (isSpanish) {
      await _save('es');
      return;
    }
    String? language = savedLanguage;
    if (language != 'en' && language != 'es') {
      try {
        final prefs = await SharedPreferences.getInstance();
        language = prefs.getString(_prefsKey(userId));
      } catch (_) {}
    }
    localeNotifier.value = language == 'es' ? 'es' : 'en';
  }

  /// Forgets the signed-in user and returns the app to English.
  static void onSignOut() {
    _userId = null;
    localeNotifier.value = 'en';
  }

  static Future<void> setLocale(String locale) async {
    localeNotifier.value = locale;
    await _save(locale);
  }

  static Future<void> toggleLocale() => setLocale(isSpanish ? 'en' : 'es');

  /// Saves [locale] as the signed-in user's preference (no-op when signed out).
  static Future<void> _save(String locale) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey(userId), locale);
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'language': locale,
      });
    } catch (e) {
      debugPrint('Could not save language to profile: $e');
    }
  }

  /// Registers [context] to rebuild when the language changes.
  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<LanguageScope>();
  }

  // ─── Installer Dashboard ──────────────────────────────
  static String get clockIn => tr('clock in', 'registrar entrada');
  static String get clockOut => tr('clock out', 'registrar salida');
  static String get finishDay => tr('finish day', 'terminar día');
  static String get startLunch => tr('start lunch', 'iniciar almuerzo');
  static String get endLunch => tr('end lunch', 'terminar almuerzo');
  static String get signOut => tr('Sign Out', 'Cerrar Sesión');
  static String get deleteAccount => tr('Delete Account', 'Eliminar Cuenta');
  static String get noInternet =>
      tr('No internet connection', 'Sin conexión a internet');

  // ─── Common UI ────────────────────────────────────────
  static String get cancel => tr('Cancel', 'Cancelar');
  static String get delete => tr('Delete', 'Eliminar');
  static String get confirm => tr('Confirm', 'Confirmar');
  static String get save => tr('Save', 'Guardar');
  static String get close => tr('Close', 'Cerrar');
  static String get loading => tr('Loading...', 'Cargando...');
  static String get today => tr('Today', 'Hoy');
  static String get dayComplete => tr('Day Complete', 'Día Completado');
  static String get crewDaysLeft =>
      tr('crew days left', 'días de equipo restantes');
  static String get noAreasAssigned =>
      tr('No areas assigned to you yet', 'Aún no tienes áreas asignadas');
  static String get selectWhatYouDid =>
      tr('What did you work on?', '¿En qué trabajaste?');

  // ─── Profile sheet ────────────────────────────────────
  static String get deleteAccountConfirmTitle =>
      tr('Delete Account?', '¿Eliminar Cuenta?');
  static String get deleteAccountConfirmBody => tr(
    'This will permanently delete your account and all your data. This action cannot be undone.',
    'Esto eliminará permanentemente tu cuenta y todos tus datos. Esta acción no se puede deshacer.',
  );

  // ─── Auth ─────────────────────────────────────────────
  static String get enterPin => tr('Enter your PIN', 'Ingresa tu PIN');
  static String get invalidPin => tr('Invalid PIN!', '¡PIN inválido!');

  // ─── Roles ────────────────────────────────────────────
  /// Display name for a stored role value (`installer`, `foreman`, ...).
  static String role(String role) {
    switch (role) {
      case 'installer':
        return tr('Installer', 'Instalador');
      case 'junior_installer':
        return tr('Junior Installer', 'Instalador Junior');
      case 'helper':
        return tr('Helper', 'Ayudante');
      case 'foreman':
        return tr('Foreman', 'Capataz');
      case 'supervisor':
        return tr('Supervisor', 'Supervisor');
      case 'admin':
        return tr('Admin', 'Administrador');
      default:
        final label = role.replaceAll('_', ' ');
        return label.isEmpty
            ? label
            : label[0].toUpperCase() + label.substring(1);
    }
  }

  // ─── Work items (clock-out descriptions) ──────────────
  /// Work items an installer picks from when clocking out. The English
  /// value is what gets saved to Firestore; never save the Spanish text.
  static const List<String> workItems = [
    'Waterproofing at shower pan',
    'Drain installation at shower pan',
    'Paper & lath',
    'Scratch',
    'Float walls',
    'Hydroban paint',
    'Layout tile',
    'Install tile',
    'Grout',
    'Float shower pan',
    'Float bath floor',
    'Apply grout',
    'Seal the tile',
  ];

  static const Map<String, String> _workItemsEs = {
    'Waterproofing at shower pan': 'Impermeabilizar el plato de ducha',
    'Drain installation at shower pan':
        'Instalar el desagüe del plato de ducha',
    'Paper & lath': 'Papel y malla',
    'Scratch': 'Capa base (scratch)',
    'Float walls': 'Flotear paredes',
    'Hydroban paint': 'Pintura Hydroban',
    'Layout tile': 'Trazar el azulejo',
    'Install tile': 'Instalar azulejo',
    'Grout': 'Lechada (grout)',
    'Float shower pan': 'Flotear el plato de ducha',
    'Float bath floor': 'Flotear el piso del baño',
    'Apply grout': 'Aplicar lechada',
    'Seal the tile': 'Sellar el azulejo',
  };

  /// Display text for one work item stored in English.
  static String workItem(String english) =>
      isSpanish ? (_workItemsEs[english] ?? english) : english;

  /// Display text for a stored description such as "Grout, Install tile".
  /// Unknown parts (free text) are shown unchanged.
  static String workDescription(String? stored) {
    if (stored == null || stored.isEmpty || !isSpanish) return stored ?? '';
    return stored.split(', ').map(workItem).join(', ');
  }
}

/// Placed above every route (via `MaterialApp.builder`) so that widgets
/// calling [AppStrings.watch] rebuild when the language changes.
class LanguageScope extends InheritedNotifier<ValueNotifier<String>> {
  LanguageScope({super.key, required super.child})
    : super(notifier: AppStrings.localeNotifier);
}
