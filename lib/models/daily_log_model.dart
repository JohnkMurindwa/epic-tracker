class DailyLogModel {
  final String id;
  final String projectId;
  final String installerId;
  final String installerName;
  final double morningSqft;
  final double afternoonSqft;
  final String? photoUrl;
  final DateTime clockIn;
  final DateTime? clockOut;
  final DateTime? lunchStart;
  final DateTime? lunchEnd;
  final DateTime date;

  DailyLogModel({
    required this.id,
    required this.projectId,
    required this.installerId,
    required this.installerName,
    required this.morningSqft,
    required this.afternoonSqft,
    this.photoUrl,
    required this.clockIn,
    this.clockOut,
    this.lunchStart,
    this.lunchEnd,
    required this.date,
  });

  // Total sqft for the day
  double get totalSqft => morningSqft + afternoonSqft;

  // Convert Firestore document to DailyLogModel
  factory DailyLogModel.fromMap(Map<String, dynamic> map, String id) {
    return DailyLogModel(
      id: id,
      projectId: map['project_id'] ?? '',
      installerId: map['installer_id'] ?? '',
      installerName: map['installer_name'] ?? '',
      morningSqft: (map['morning_sqft'] ?? 0).toDouble(),
      afternoonSqft: (map['afternoon_sqft'] ?? 0).toDouble(),
      photoUrl: map['photo_url'],
      clockIn: map['clock_in']?.toDate() ?? DateTime.now(),
      clockOut: map['clock_out']?.toDate(),
      lunchStart: map['lunch_start']?.toDate(),
      lunchEnd: map['lunch_end']?.toDate(),
      date: map['date']?.toDate() ?? DateTime.now(),
    );
  }

  // Convert DailyLogModel to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'project_id': projectId,
      'installer_id': installerId,
      'installer_name': installerName,
      'morning_sqft': morningSqft,
      'afternoon_sqft': afternoonSqft,
      'photo_url': photoUrl,
      'clock_in': clockIn,
      'clock_out': clockOut,
      'lunch_start': lunchStart,
      'lunch_end': lunchEnd,
      'date': date,
    };
  }
}
