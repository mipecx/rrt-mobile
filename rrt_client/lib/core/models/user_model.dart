class UserModel {
  final String id;
  final String phone;
  final String fullName;
  final String role; // 'tourist', 'rrt', 'dispatcher'

  UserModel({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? json['user_id'] ?? '',
      phone: json['phone'] ?? '',
      fullName: json['full_name'] ?? json['fullName'] ?? json['name'] ?? '',
      role: json['role'] ?? 'tourist',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'full_name': fullName,
      'role': role,
    };
  }
}
