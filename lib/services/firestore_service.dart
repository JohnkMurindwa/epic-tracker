import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Projects Collection
  CollectionReference get projects => _db.collection('projects');

  // Users Collection
  CollectionReference get users => _db.collection('users');

  // Daily Logs Collection
  CollectionReference get dailyLogs => _db.collection('daily_logs');

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

  // Update project
  Future<void> updateProject({
    required String projectId,
    required String name,
    required String location,
    required double totalSqft,
  }) async {
    await projects.doc(projectId).update({
      'name': name,
      'location': location,
      'total_sqft': totalSqft,
    });
  }

  // Update project status
  Future<void> updateProjectStatus({
    required String projectId,
    required String status,
  }) async {
    await projects.doc(projectId).update({'status': status});
  }

  // Clock In
  Future<void> clockIn({
    required String userId,
    required String userName,
    required GeoPoint location,
  }) async {
    await dailyLogs.add({
      'installer_id': userId,
      'installer_name': userName,
      'clock_in': FieldValue.serverTimestamp(),
      'location': location,
      'morning_sqft': 0,
      'afternoon_sqft': 0,
      'total_sqft': 0,
      'date': FieldValue.serverTimestamp(),
    });
  }

  // Update Lunch
  Future<void> updateLunch({
    required String userId,
    required bool isStarting,
  }) async {
    QuerySnapshot logs = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .orderBy('date', descending: true)
        .limit(1)
        .get();

    if (logs.docs.isNotEmpty) {
      await logs.docs.first.reference.update({
        isStarting ? 'lunch_start' : 'lunch_end': FieldValue.serverTimestamp(),
      });
    }
  }

  // Clock Out
  Future<void> clockOut({
    required String userId,
    required double morningSqft,
    required double afternoonSqft,
    String? morningPhotoUrl,
    String? afternoonPhotoUrl,
  }) async {
    QuerySnapshot logs = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .orderBy('date', descending: true)
        .limit(1)
        .get();

    if (logs.docs.isNotEmpty) {
      await logs.docs.first.reference.update({
        'clock_out': FieldValue.serverTimestamp(),
        'morning_sqft': morningSqft,
        'afternoon_sqft': afternoonSqft,
        'total_sqft': morningSqft + afternoonSqft,
        'morning_photo_url': morningPhotoUrl,
        'afternoon_photo_url': afternoonPhotoUrl,
      });
    }
  }

  // Get today's log for installer
  Stream<QuerySnapshot> getTodayLog(String userId) {
    DateTime now = DateTime.now();
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    DateTime endOfDay = startOfDay.add(const Duration(days: 1));

    return dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: startOfDay)
        .where('date', isLessThan: endOfDay)
        .snapshots();
  }

  // Get all logs for a project
  Stream<QuerySnapshot> getProjectLogs(String projectId) {
    return dailyLogs
        .where('project_id', isEqualTo: projectId)
        .orderBy('date', descending: true)
        .snapshots();
  }
}
