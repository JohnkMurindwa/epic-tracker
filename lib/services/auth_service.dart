import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<UserModel?> signUp({
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

      // Generate 5 digit PIN only for installers and site leaders
      String pin = '';
      if (role == 'installer' || role == 'site_leader') {
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

      return user;
    } catch (e) {
      print('Sign up error: $e');
      return null;
    }
  }

  // Sign in with email and password
  Future<UserModel?> signInWithEmail({
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

      return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      print('Sign in error: $e');
      return null;
    }
  }

  // Sign in with PIN (installers and site leaders only)
  Future<UserModel?> signInWithPin(String pin) async {
    try {
      QuerySnapshot result = await _db
          .collection('users')
          .where('pin', isEqualTo: pin)
          .where('role', whereIn: ['installer', 'site_leader'])
          .get();

      if (result.docs.isEmpty) return null;

      return UserModel.fromMap(
        result.docs.first.data() as Map<String, dynamic>,
        result.docs.first.id,
      );
    } catch (e) {
      print('PIN sign in error: $e');
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
      print('Get user error: $e');
      return null;
    }
  }
}
