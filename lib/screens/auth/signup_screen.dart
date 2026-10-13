import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/app_strings.dart';
import '../../widgets/language_toggle.dart';
import '../../models/user_model.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final AuthService _authService = AuthService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _selectedRole = 'installer';

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(tr('Create Account', 'Crear Cuenta')),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: LanguageToggle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                tr('Join Epic Stone', 'Únete a Epic Stone'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Fill in your details to get started',
                  'Completa tus datos para comenzar',
                ),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Full Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: tr('Full Name', 'Nombre completo'),
                  prefixIcon: const Icon(Icons.person_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.black87,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Email
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: tr('Email Address', 'Correo electrónico'),
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.black87,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Phone
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: tr('Phone Number', 'Número de teléfono'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.black87,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Password
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr('Password', 'Contraseña'),
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.black87,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Role Selection
              Text(
                tr('What is your role?', '¿Cuál es tu puesto?'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildRoleChip(AppStrings.role('installer'), 'installer'),
                  _buildRoleChip(
                    tr('Junior Installer', 'Instalador Junior'),
                    'junior_installer',
                  ),
                  _buildRoleChip(tr('Helper', 'Ayudante'), 'helper'),
                  _buildRoleChip(AppStrings.role('foreman'), 'foreman'),
                ],
              ),
              const SizedBox(height: 32),

              // Sign Up Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          tr('Create Account', 'Crear Cuenta'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Already have account
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(tr('Already have an account? ', '¿Ya tienes cuenta? ')),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      tr('Sign In', 'Iniciar Sesión'),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _signUp() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Please fill in all fields!',
              '¡Por favor llena todos los campos!',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Checked here rather than relying on Firebase: on Android its
    // weak-password error can fail to come back, leaving the button spinning.
    if (_passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Password must be at least 6 characters!',
              '¡La contraseña debe tener al menos 6 caracteres!',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _authService.signUp(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        role: _selectedRole,
      );

      if (response['success'] == true && mounted) {
        UserModel user = response['user'];

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(tr('Account Created!', '¡Cuenta Creada!')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Your 5 digit PIN is:', 'Tu PIN de 5 dígitos es:')),
                const SizedBox(height: 16),
                Text(
                  user.pin,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr(
                    'Save this PIN! You will use it to login every day.',
                    '¡Guarda este PIN! Lo usarás para entrar todos los días.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  tr('Got it! Go to Login', '¡Listo! Ir a Iniciar Sesión'),
                ),
              ),
            ],
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response['message'] ??
                    tr('Sign up failed!', '¡Error al crear la cuenta!'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRoleChip(String label, String role) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black87 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.black87 : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
