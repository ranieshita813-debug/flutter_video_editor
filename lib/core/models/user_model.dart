class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.isGuest = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? 'user_guest',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Guest User',
      avatarUrl: json['avatarUrl'] as String?,
      isGuest: json['isGuest'] as bool? ?? false,
    );
  }

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final bool isGuest;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'isGuest': isGuest,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    bool? isGuest,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}
