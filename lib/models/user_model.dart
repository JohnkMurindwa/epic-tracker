class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String pin;
  final String? currentProjectId;
  final bool isActive;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.pin,
    this.currentProjectId,
    required this.isActive,
  });

  // Convert Firestore document to UserModel
  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'installer',
      pin: map['pin'] ?? '',
      currentProjectId: map['current_project_id'],
      isActive: map['is_active'] ?? true,
    );
  }

  // Convert UserModel to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'pin': pin,
      'current_project_id': currentProjectId,
      'is_active': isActive,
    };
  }
}
