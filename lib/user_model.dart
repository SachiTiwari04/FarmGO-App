// lib/user_model.dart
class AppUser {
  final String fullName;
  final String farmLocation;
  final String farmType;
  final String email;

  AppUser({
    required this.fullName,
    required this.farmLocation,
    required this.farmType,
    required this.email,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      fullName: map['fullName'] ?? '',
      farmLocation: map['farmLocation'] ?? '',
      farmType: map['farmType'] ?? '',
      email: map['email'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'farmLocation': farmLocation,
      'farmType': farmType,
      'email': email,
    };
  }
}