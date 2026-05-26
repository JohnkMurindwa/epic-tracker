class ProjectModel {
  final String id;
  final String name;
  final String location;
  final double totalSqft;
  final double completedSqft;
  final String status;
  final DateTime createdAt;

  ProjectModel({
    required this.id,
    required this.name,
    required this.location,
    required this.totalSqft,
    required this.completedSqft,
    required this.status,
    required this.createdAt,
  });

  // Calculate percentage
  double get progressPercentage {
    if (totalSqft == 0) return 0;
    return (completedSqft / totalSqft) * 100;
  }

  // Calculate remaining sqft
  double get remainingSqft => totalSqft - completedSqft;

  // Convert Firestore document to ProjectModel
  factory ProjectModel.fromMap(Map<String, dynamic> map, String id) {
    return ProjectModel(
      id: id,
      name: map['name'] ?? '',
      location: map['location'] ?? '',
      totalSqft: (map['total_sqft'] ?? 0).toDouble(),
      completedSqft: (map['completed_sqft'] ?? 0).toDouble(),
      status: map['status'] ?? 'active',
      createdAt: map['created_at']?.toDate() ?? DateTime.now(),
    );
  }

  // Convert ProjectModel to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location,
      'total_sqft': totalSqft,
      'completed_sqft': completedSqft,
      'status': status,
      'created_at': createdAt,
    };
  }
}
