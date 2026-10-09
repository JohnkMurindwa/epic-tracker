import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collections
  CollectionReference get projects => _db.collection('projects');
  CollectionReference get users => _db.collection('users');
  CollectionReference get dailyLogs => _db.collection('daily_logs');
  CollectionReference get crews => _db.collection('crews');

  /// How long clock in/out actions wait for the server before moving on.
  static const _serverWait = Duration(seconds: 3);

  /// Waits for a write to reach the server, but no longer than [_serverWait].
  ///
  /// Firestore saves every write on the device immediately and sends it
  /// when the connection returns, but the write's Future only completes
  /// once the server confirms. Offline that never happens, so awaiting it
  /// directly would leave clock in/out spinning forever.
  Future<void> _queuedWrite(Future<void> write) async {
    try {
      await write.timeout(_serverWait);
    } on TimeoutException {
      // Offline or slow: saved locally, will sync automatically.
    }
  }

  // ─── PROJECTS / JOB SITES ────────────────────────────────

  Future<void> addProject({
    required String name,
    required String location,
  }) async {
    await projects.add({
      'name': name,
      'location': location,
      'status': 'active',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getProjects() {
    return projects.orderBy('created_at', descending: true).snapshots();
  }

  Future<void> updateProject({
    required String projectId,
    required String name,
    required String location,
  }) async {
    await projects.doc(projectId).update({'name': name, 'location': location});
  }

  Future<void> updateProjectStatus({
    required String projectId,
    required String status,
  }) async {
    await projects.doc(projectId).update({'status': status});
  }

  // ─── AREAS (within job sites) ─────────────────────────────

  Future<String> addArea({
    required String projectId,
    required String projectName,
    required String levelName,
    required String areaName,
    required double totalCrewDays,
  }) async {
    final doc = await _db.collection('areas').add({
      'projectId': projectId,
      'projectName': projectName,
      'levelName': levelName,
      'name': areaName,
      'totalCrewDays': totalCrewDays,
      'consumedCrewDays': 0.0,
      'assignedPeople': <String>[],
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<QuerySnapshot> getAreasForProject(String projectId) {
    return _db
        .collection('areas')
        .where('projectId', isEqualTo: projectId)
        .snapshots();
  }

  Future<void> updateArea({
    required String areaId,
    required String name,
    required double totalCrewDays,
  }) async {
    await _db.collection('areas').doc(areaId).update({
      'name': name,
      'totalCrewDays': totalCrewDays,
    });
  }

  /// Delete an area. Historical daily_logs entries referencing it
  /// are preserved — only the area document itself is removed.
  Future<void> deleteArea(String areaId) async {
    await _db.collection('areas').doc(areaId).delete();
  }

  /// Assign a worker to a job site's pool.
  Future<void> assignWorkerToProject({
    required String projectId,
    required String workerId,
  }) async {
    await _db.collection('projects').doc(projectId).update({
      'assignedWorkers': FieldValue.arrayUnion([workerId]),
    });
  }

  /// Remove a worker from a job site's pool.
  Future<void> removeWorkerFromProject({
    required String projectId,
    required String workerId,
  }) async {
    await _db.collection('projects').doc(projectId).update({
      'assignedWorkers': FieldValue.arrayRemove([workerId]),
    });
  }

  /// Assign a foreman to a project.
  Future<void> assignForemanToProject({
    required String projectId,
    required String foremanId,
  }) async {
    await _db.collection('projects').doc(projectId).update({
      'assignedForemen': FieldValue.arrayUnion([foremanId]),
    });
  }

  /// Remove a foreman from a project.
  Future<void> removeForemanFromProject({
    required String projectId,
    required String foremanId,
  }) async {
    await _db.collection('projects').doc(projectId).update({
      'assignedForemen': FieldValue.arrayRemove([foremanId]),
    });
  }

  Future<void> assignPeopleToArea({
    required String areaId,
    required List<String> peopleIds,
  }) async {
    await _db.collection('areas').doc(areaId).update({
      'assignedPeople': peopleIds,
    });
  }

  /// Assign a person to an area. Automatically removes them from any
  /// other area they were assigned to (one person = one area at a time).
  /// Historical time entries are never touched.
  Future<void> addPersonToArea({
    required String areaId,
    required String userId,
  }) async {
    // Remove from all other areas first
    final currentAssignments = await _db
        .collection('areas')
        .where('assignedPeople', arrayContains: userId)
        .get();

    for (final doc in currentAssignments.docs) {
      if (doc.id != areaId) {
        await doc.reference.update({
          'assignedPeople': FieldValue.arrayRemove([userId]),
        });
      }
    }

    // Add to the new area
    await _db.collection('areas').doc(areaId).update({
      'assignedPeople': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> removePersonFromArea({
    required String areaId,
    required String userId,
  }) async {
    await _db.collection('areas').doc(areaId).update({
      'assignedPeople': FieldValue.arrayRemove([userId]),
    });
  }

  // ─── DAILY LOGS (area-based time tracking) ────────────────

  /// Clock in at a specific area. Creates or updates today's daily log.
  ///
  /// Foremen clock in at a whole job site: [areaId] and [areaName] are null,
  /// and their hours are not counted against any area's crew days.
  Future<void> clockInToArea({
    required String userId,
    required String userName,
    required String userRole,
    required String projectId,
    required String projectName,
    required GeoPoint location,
    String? areaId,
    String? areaName,
    String? levelName,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // Check if there's already a daily log for today
    final existing = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    final timeEntry = {
      'areaId': areaId,
      'areaName': areaName,
      'projectId': projectId,
      'projectName': projectName,
      'levelName': areaId == null ? null : (levelName ?? 'Unassigned'),
      'clockIn': Timestamp.now(),
      'clockOut': null,
      'description': null,
      'hoursWorked': 0,
    };

    if (existing.docs.isEmpty) {
      // Create new daily log
      // doc().set() rather than add(): add() waits for the server.
      await _queuedWrite(
        dailyLogs.doc().set({
          'installer_id': userId,
          'installer_name': userName,
          'installer_role': userRole,
          'log_date': Timestamp.fromDate(todayStart),
          'date': FieldValue.serverTimestamp(),
          'location': location,
          'time_entries': [timeEntry],
          'photo_url': null,
          'is_day_complete': false,
        }),
      );
    } else {
      // Add new time entry to existing log
      await _queuedWrite(
        existing.docs.first.reference.update({
          'time_entries': FieldValue.arrayUnion([timeEntry]),
        }),
      );
    }
  }

  /// Clock out of current area. Updates the last time entry.
  /// Hours worked exclude any lunch break taken during this session.
  Future<void> clockOutOfArea({
    required String userId,
    required String description,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return;
    await _closeOpenEntry(
      snapshot.docs.first,
      userId: userId,
      description: description,
      clockOut: now,
    );
  }

  /// Clock out a session the user forgot to close, at the time they say
  /// they left. Works for today's log or an earlier day's.
  Future<void> clockOutMissed({
    required String logId,
    required String userId,
    required DateTime leftAt,
  }) async {
    final doc = await dailyLogs.doc(logId).get();
    if (!doc.exists) return;
    await _closeOpenEntry(
      doc,
      userId: userId,
      description: missedClockOutDescription,
      clockOut: leftAt,
      missed: true,
    );
  }

  /// Stored description for a session closed through the missed clock-out
  /// dialog (English, like all stored descriptions).
  static const missedClockOutDescription = 'Forgot to clock out';

  /// Daily logs from the last [days] days (today included) whose last
  /// time entry was never clocked out, oldest first.
  Future<List<Map<String, dynamic>>> getLogsWithOpenEntry(
    String userId, {
    int days = 14,
  }) async {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day - days);

    // Two equality filters: served by single-field indexes, no composite
    // index needed. Date filtering happens below.
    final snapshot = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('is_day_complete', isEqualTo: false)
        .get();

    final open = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final logDate = (data['log_date'] as Timestamp?)?.toDate();
      if (logDate == null || logDate.isBefore(cutoff)) continue;
      final entries = List<Map<String, dynamic>>.from(
        data['time_entries'] ?? [],
      );
      if (entries.isNotEmpty && entries.last['clockOut'] == null) {
        open.add({'id': doc.id, ...data});
      }
    }
    open.sort(
      (a, b) =>
          (a['log_date'] as Timestamp).compareTo(b['log_date'] as Timestamp),
    );
    return open;
  }

  /// Closes the open (last) time entry of [doc] at [clockOut].
  /// Hours worked exclude any lunch break taken during the session; a lunch
  /// that was never ended is treated as lasting until [clockOut].
  Future<void> _closeOpenEntry(
    DocumentSnapshot doc, {
    required String userId,
    required String description,
    required DateTime clockOut,
    bool missed = false,
  }) async {
    final data = doc.data() as Map<String, dynamic>;
    final entries = List<Map<String, dynamic>>.from(data['time_entries'] ?? []);

    if (entries.isEmpty) return;

    // Find the last entry (the one without a clockOut)
    final lastIndex = entries.length - 1;
    final lastEntry = entries[lastIndex];
    if (lastEntry['clockOut'] != null) return;

    // Calculate hours worked
    final clockIn = (lastEntry['clockIn'] as Timestamp?)?.toDate() ?? clockOut;
    double hoursWorked = clockOut.difference(clockIn).inMinutes / 60.0;

    // Subtract lunch if it happened during THIS session
    final isOnLunch = data['is_on_lunch'] == true;
    final lunchStart = (data['lunch_start'] as Timestamp?)?.toDate();
    final lunchEnd = isOnLunch
        ? clockOut
        : (data['lunch_end'] as Timestamp?)?.toDate();
    if (lunchStart != null && lunchEnd != null) {
      // Lunch happened within this session's window?
      if (lunchStart.isAfter(clockIn) && !lunchEnd.isAfter(clockOut)) {
        final lunchMinutes = lunchEnd.difference(lunchStart).inMinutes;
        hoursWorked -= lunchMinutes / 60.0;
      }
    }
    if (hoursWorked < 0) hoursWorked = 0;

    // Update crew days consumed for this area, then snapshot the
    // remaining count into the entry so history can show the countdown.
    // Foremen clock in at a whole site (no area), so nothing is consumed.
    final areaId = lastEntry['areaId'] as String?;
    double? crewDaysLeftSnapshot;
    if (areaId != null) {
      await _updateCrewDaysConsumed(areaId, userId, hoursWorked);

      // Read back the area's new state for the snapshot
      final areaDoc = await _db.collection('areas').doc(areaId).get();
      if (areaDoc.exists) {
        final areaData = areaDoc.data() as Map<String, dynamic>;
        final total = (areaData['totalCrewDays'] ?? 0).toDouble();
        final consumed = (areaData['consumedCrewDays'] ?? 0).toDouble();
        final peopleCount = (areaData['assignedPeople'] as List?)?.length ?? 0;
        final pairs = peopleCount / 2;
        final remaining = total - consumed;
        crewDaysLeftSnapshot = pairs > 0 ? remaining / pairs : remaining;
      }
    }

    // Update the entry (with snapshot if available)
    entries[lastIndex] = {
      ...lastEntry,
      'clockOut': Timestamp.fromDate(clockOut),
      'description': description,
      'hoursWorked': double.parse(hoursWorked.toStringAsFixed(2)),
      if (missed) 'clockOutMissed': true,
      if (crewDaysLeftSnapshot != null)
        'crewDaysLeftAfter': double.parse(
          crewDaysLeftSnapshot.toStringAsFixed(1),
        ),
    };

    await _queuedWrite(
      doc.reference.update({
        'time_entries': entries,
        if (isOnLunch) 'is_on_lunch': false,
        if (isOnLunch) 'lunch_end': Timestamp.fromDate(clockOut),
      }),
    );
  }

  /// Update crew days consumed based on hours worked.
  /// Formula: crew days consumed = (people × hours) / 16
  /// Per person: hours / 16
  Future<void> _updateCrewDaysConsumed(
    String areaId,
    String userId,
    double hoursWorked,
  ) async {
    // Each person contributes hours/16 crew days
    final crewDaysContributed = hoursWorked / 16.0;

    await _queuedWrite(
      _db.collection('areas').doc(areaId).update({
        'consumedCrewDays': FieldValue.increment(crewDaysContributed),
      }),
    );
  }

  /// Save end-of-day photo.
  Future<void> saveDayPhoto({
    required String userId,
    required String photoUrl,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      await snapshot.docs.first.reference.update({'photo_url': photoUrl});
    }
  }

  /// Start lunch. A pause: the open time entry stays open, and the lunch
  /// time is subtracted from hours when the user clocks out.
  Future<void> startLunch({required String userId}) => _updateTodaysLog(
    userId,
    {'is_on_lunch': true, 'lunch_start': Timestamp.now()},
  );

  Future<void> endLunch({required String userId}) => _updateTodaysLog(userId, {
    'is_on_lunch': false,
    'lunch_end': Timestamp.now(),
  });

  Future<void> _updateTodaysLog(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      await _queuedWrite(snapshot.docs.first.reference.update(data));
    }
  }

  /// Mark day as complete (final clock out).
  Future<void> completeDayLog({required String userId}) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      await _queuedWrite(
        snapshot.docs.first.reference.update({'is_day_complete': true}),
      );
    }
  }

  /// Get today's log for a user.
  Future<Map<String, dynamic>?> getTodaysLog(String userId) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return {
      'id': snapshot.docs.first.id,
      ...snapshot.docs.first.data() as Map<String, dynamic>,
    };
  }

  /// Stream today's log for live updates.
  Stream<QuerySnapshot> streamTodaysLog(String userId) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return dailyLogs
        .where('installer_id', isEqualTo: userId)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .snapshots();
  }

  /// Get the user's currently assigned area.
  Future<Map<String, dynamic>?> getAssignedArea(String userId) async {
    final snapshot = await _db
        .collection('areas')
        .where('assignedPeople', arrayContains: userId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return {'id': snapshot.docs.first.id, ...snapshot.docs.first.data()};
  }

  /// Get all areas assigned to a user.
  Future<List<Map<String, dynamic>>> getAssignedAreas(String userId) async {
    final snapshot = await _db
        .collection('areas')
        .where('assignedPeople', arrayContains: userId)
        .where('status', isEqualTo: 'active')
        .get();

    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }
}
