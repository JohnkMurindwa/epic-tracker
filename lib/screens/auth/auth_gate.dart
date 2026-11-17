import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/app_strings.dart';
import '../../services/auth_service.dart';
import '../admin/admin_dashboard.dart';
import '../installer/installer_dashboard.dart';
import '../supervisor/supervisor_dashboard.dart';
import 'login_screen.dart';

/// Decides the first screen when the app launches.
///
/// Firebase keeps the auth session on the device between launches, but the
/// app used to open straight on the login screen without looking at it —
/// which is why everyone had to sign in again every time. This widget reads
/// the stored session and sends the user straight to their dashboard; the
/// login screen only appears when nobody is signed in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  Widget? _screen;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final UserModel? user = await _authService.restoreSession();
    if (!mounted) return;

    if (user == null) {
      setState(() => _screen = const LoginScreen());
      return;
    }

    // Same follow-up as a fresh login.
    await AppStrings.onSignIn(user.id, user.language);
    if (!mounted) return;

    Widget dashboard;
    if (kIsWeb || user.role == 'admin') {
      // The admin dashboard is English-only.
      AppStrings.useEnglishOnly();
      dashboard = AdminDashboard(user: user);
    } else if (user.role == 'supervisor' || user.role == 'foreman') {
      dashboard = SupervisorDashboard(user: user);
    } else {
      dashboard = InstallerDashboard(user: user);
    }
    setState(() => _screen = dashboard);
  }

  @override
  Widget build(BuildContext context) {
    // Brief branded splash while the session is checked (usually <1s).
    return _screen ?? _buildSplash();
  }

  Widget _buildSplash() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              // The official brand lockup — same asset as splash and login.
              child: Image.asset(
                'assets/icon/epic_logo.png',
                width: 220,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.black87,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
