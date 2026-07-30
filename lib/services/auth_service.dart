import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
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
      // Create auth account
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Generate 5 digit PIN only for installers
      String pin = '';
      if (role == 'installer') {
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
      );

      await _db.collection('users').doc(result.user!.uid).set(user.toMap());

      return {'success': true, 'user': user};
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign up error: ${e.code}');
      String message = '';
      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered!';
          break;
        case 'weak-password':
          message = 'Password must be at least 6 characters!';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address!';
          break;
        default:
          message = 'Sign up failed: ${e.message}';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      debugPrint('Sign up error: $e');
      return {'success': false, 'message': 'Something went wrong. Try again!'};
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
          message = 'No account found with this email!';
          break;
        case 'wrong-password':
          message = 'Incorrect password!';
          break;
        case 'invalid-credential':
          message = 'Invalid email or password!';
          break;
        default:
          message = 'Sign in failed: ${e.message}';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      debugPrint('Sign in error: $e');
      return {'success': false, 'message': 'Something went wrong. Try again!'};
    }
  }

  // Sign in with PIN (installers and site leaders only)
  Future<UserModel?> signInWithPin(String pin) async {
    try {
      QuerySnapshot result = await _db
          .collection('users')
          .where('pin', isEqualTo: pin)
          .where('role', isEqualTo: 'installer')
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
