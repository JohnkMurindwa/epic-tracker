import 'package:flutter/material.dart';
import '../services/app_strings.dart';

/// Compact button that switches the app between English and Español.
/// Shows the language you can switch *to*, so a Spanish-only reader
/// always sees "Español" while the app is in English.
class LanguageToggle extends StatelessWidget {
  final Color? color;

  const LanguageToggle({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    final fg = color ?? Colors.black87;
    return TextButton.icon(
      onPressed: AppStrings.toggleLocale,
      icon: Icon(Icons.language, size: 18, color: fg),
      label: Text(
        AppStrings.isSpanish ? 'English' : 'Español',
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: fg.withValues(alpha: 0.25)),
        ),
      ),
    );
  }
}
