import 'dart:convert';

enum UserStatus { pending, approved, rejected }

class VinlandUser {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String passwordHash;
  final UserStatus status;
  final bool isAdmin;
  final DateTime createdAt;

  VinlandUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.passwordHash,
    this.status = UserStatus.pending,
    this.isAdmin = false,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'passwordHash': passwordHash,
        'status': status.name,
        'isAdmin': isAdmin,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VinlandUser.fromJson(Map<String, dynamic> json) => VinlandUser(
        id: json['id']?.toString() ?? '',
        firstName: json['firstName']?.toString() ?? '',
        lastName: json['lastName']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        passwordHash: json['passwordHash']?.toString() ?? '',
        status:
            UserStatus.values.byName(json['status']?.toString() ?? 'pending'),
        isAdmin: json['isAdmin'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  VinlandUser copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? email,
    String? passwordHash,
    UserStatus? status,
    bool? isAdmin,
    DateTime? createdAt,
  }) =>
      VinlandUser(
        id: id ?? this.id,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        email: email ?? this.email,
        passwordHash: passwordHash ?? this.passwordHash,
        status: status ?? this.status,
        isAdmin: isAdmin ?? this.isAdmin,
        createdAt: createdAt ?? this.createdAt,
      );
}
