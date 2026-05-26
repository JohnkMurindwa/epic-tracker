import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Projects Collection
  CollectionReference get projects => _db.collection('projects');

  // Users Collection
  CollectionReference get users => _db.collection('users');

  // Add a new project
  Future<void> addProject({
    required String name,
    required String location,
    required double totalSqft,
  }) async {
    await projects.add({
      'name': name,
      'location': location,
      'total_sqft': totalSqft,
      'completed_sqft': 0,
      'status': 'active',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // Get all projects
  Stream<QuerySnapshot> getProjects() {
    return projects.orderBy('created_at', descending: true).snapshots();
  }

  // Update completed sqft
  Future<void> updateProgress({
    required String projectId,
    required double sqftToAdd,
  }) async {
    await projects.doc(projectId).update({
      'completed_sqft': FieldValue.increment(sqftToAdd),
    });
  }
}
