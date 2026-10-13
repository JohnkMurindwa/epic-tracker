import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'app_strings.dart';
import 'notification_service.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<Map<String, dynamic>> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    try {
      // Create auth account. The timeout stops the sign-up button spinning
      // forever if Firebase never answers (seen on Android).
      UserCredential result = await _auth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 20));

      // Generate 5 digit PIN for all installation workers
      String pin = '';
      if (role == 'installer' ||
          role == 'junior_installer' ||
          role == 'helper' ||
          role == 'foreman') {
        pin = _generatePin();
      }

      // Create user in Firestore
      UserModel user = UserModel(
        id: result.user!.uid,
        name: name,
        email: email,
        phone: phone,
        role: role,
        pin: pin,
        isActive: true,
        language: AppStrings.locale,
      );

      await _db.collection('users').doc(result.user!.uid).set(user.toMap());

      return {'success': true, 'user': user};
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign up error: ${e.code}');
      String message = '';
      switch (e.code) {
        case 'email-already-in-use':
          message = tr(
            'This email is already registered!',
            '¡Este correo ya está registrado!',
          );
          break;
        case 'weak-password':
          message = tr(
            'Password must be at least 6 characters!',
            '¡La contraseña debe tener al menos 6 caracteres!',
          );
          break;
        case 'invalid-email':
          message = tr(
            'Please enter a valid email address!',
            '¡Ingresa un correo electrónico válido!',
          );
          break;
        default:
          message = tr(
            'Sign up failed: ${e.message}',
            'Error al crear la cuenta: ${e.message}',
          );
      }
      return {'success': false, 'message': message};
    } on TimeoutException {
      return {
        'success': false,
        'message': tr(
          'No response from the server. Check your connection and try again.',
          'Sin respuesta del servidor. Revisa tu conexión e inténtalo de nuevo.',
        ),
      };
    } catch (e) {
      debugPrint('Sign up error: $e');
      return {
        'success': false,
        'message': tr(
          'Something went wrong. Try again!',
          'Algo salió mal. ¡Inténtalo de nuevo!',
        ),
      };
    }
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      DocumentSnapshot doc = await _db
          .collection('users')
          .doc(result.user!.uid)
          .get();

      UserModel user = UserModel.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      return {'success': true, 'user': user};
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign in error: ${e.code}');
      String message = '';
      switch (e.code) {
        case 'user-not-found':
          message = tr(
            'No account found with this email!',
            '¡No hay ninguna cuenta con este correo!',
          );
          break;
        case 'wrong-password':
          message = tr('Incorrect password!', '¡Contraseña incorrecta!');
          break;
        case 'invalid-credential':
          message = tr(
            'Invalid email or password!',
            '¡Correo o contraseña inválidos!',
          );
          break;
        default:
          message = tr(
            'Sign in failed: ${e.message}',
            'Error al iniciar sesión: ${e.message}',
          );
      }
      return {'success': false, 'message': message};
    } catch (e) {
      debugPrint('Sign in error: $e');
      return {
        'success': false,
        'message': tr(
          'Something went wrong. Try again!',
          'Algo salió mal. ¡Inténtalo de nuevo!',
        ),
      };
    }
  }

  // Sign in with PIN (installers and site leaders only)
  Future<UserModel?> signInWithPin(String pin) async {
    try {
      QuerySnapshot result = await _db
          .collection('users')
          .where('pin', isEqualTo: pin)
          .where(
            'role',
            whereIn: ['installer', 'junior_installer', 'helper', 'foreman'],
          )
          .get();

      if (result.docs.isEmpty) return null;

      // Create a Firebase Auth session so Storage/Firestore rules work
      await _auth.signInAnonymously();

      return UserModel.fromMap(
        result.docs.first.data() as Map<String, dynamic>,
        result.docs.first.id,
      );
    } catch (e) {
      debugPrint('PIN sign in error: $e');
      return null;
    }
  }

  // Generate random 5 digit PIN
  String _generatePin() {
    final random = DateTime.now().millisecondsSinceEpoch % 90000 + 10000;
    return random.toString();
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    AppStrings.onSignOut();
  }

  // Delete account — removes Firestore doc and Firebase Auth user
  Future<Map<String, dynamic>> deleteAccount(String userId) async {
    try {
      // Delete Firestore user document
      await _db.collection('users').doc(userId).delete();

      // Delete Firebase Auth account (if signed in with email)
      final user = _auth.currentUser;
      if (user != null && !user.isAnonymous) {
        await user.delete();
      } else {
        // PIN users are anonymous — just sign out
        await _auth.signOut();
      }
      AppStrings.onSignOut();
      NotificationService.cancelClockOutReminder();

      return {'success': true};
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return {
          'success': false,
          'message': tr(
            'For security, please sign out and sign back in, then try deleting your account again.',
            'Por seguridad, cierra sesión y vuelve a iniciarla, luego intenta eliminar tu cuenta otra vez.',
          ),
        };
      }
      return {
        'success': false,
        'message': tr(
          'Failed to delete account: ${e.message}',
          'No se pudo eliminar la cuenta: ${e.message}',
        ),
      };
    } catch (e) {
      debugPrint('Delete account error: $e');
      return {
        'success': false,
        'message': tr(
          'Something went wrong. Try again!',
          'Algo salió mal. ¡Inténtalo de nuevo!',
        ),
      };
    }
  }

  // Get user details
  Future<UserModel?> getUserDetails(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();

      return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      debugPrint('Get user error: $e');
      return null;
    }
  }
}
