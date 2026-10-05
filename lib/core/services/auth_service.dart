import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:flutter_video_editor/core/models/user_model.dart';

class AuthService {
  AuthService();

  UserModel? _currentUser;
  final Map<String, String> _userCredentials = <String, String>{};
  final Map<String, UserModel> _usersByEmail = <String, UserModel>{};

  UserModel? get currentUser => _currentUser;

  Future<File> get _sessionFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user_session.json');
  }

  Future<File> get _dbFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/users_db.json');
  }

  Future<void> _loadUsersDb() async {
    try {
      final file = await _dbFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final usersMap = json['users'] as Map<String, dynamic>? ?? {};
        final credsMap = json['creds'] as Map<String, dynamic>? ?? {};

        _usersByEmail.clear();
        _userCredentials.clear();

        usersMap.forEach((email, userData) {
          _usersByEmail[email] = UserModel.fromJson(userData as Map<String, dynamic>);
        });

        credsMap.forEach((email, password) {
          _userCredentials[email] = password.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveUsersDb() async {
    try {
      final file = await _dbFile;
      final data = <String, dynamic>{
        'users': _usersByEmail.map((k, v) => MapEntry(k, v.toJson())),
        'creds': _userCredentials,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<UserModel?> loadSavedSession() async {
    await _loadUsersDb();
    try {
      final file = await _sessionFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(json);
        return _currentUser;
      }
    } catch (_) {}

    _currentUser = const UserModel(
      id: 'guest_01',
      email: 'guest@motiongr.app',
      displayName: 'Guest User',
      isGuest: true,
    );
    return _currentUser;
  }

  Future<void> _saveSession(UserModel user) async {
    try {
      final file = await _sessionFile;
      await file.writeAsString(jsonEncode(user.toJson()));
    } catch (_) {}
  }

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _loadUsersDb();
    if (email.trim().isEmpty || password.trim().isEmpty) {
      throw Exception('Email and password cannot be empty');
    }
    final normalizedEmail = email.trim().toLowerCase();
    if (_usersByEmail.containsKey(normalizedEmail)) {
      throw Exception('Account already exists for this email');
    }

    final user = UserModel(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      email: normalizedEmail,
      displayName: displayName.trim().isEmpty ? 'User' : displayName.trim(),
      isGuest: false,
    );

    _userCredentials[normalizedEmail] = password;
    _usersByEmail[normalizedEmail] = user;
    _currentUser = user;

    await _saveUsersDb();
    await _saveSession(user);
    return user;
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    await _loadUsersDb();
    final normalizedEmail = email.trim().toLowerCase();
    if (!_usersByEmail.containsKey(normalizedEmail)) {
      return signUp(
        email: email,
        password: password,
        displayName: normalizedEmail.split('@').first,
      );
    }

    if (_userCredentials[normalizedEmail] != password) {
      throw Exception('Invalid email or password');
    }

    final user = _usersByEmail[normalizedEmail]!;
    _currentUser = user;
    await _saveSession(user);
    return user;
  }

  Future<UserModel> signInAsGuest() async {
    final guest = UserModel(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      email: 'guest@motiongr.app',
      displayName: 'Guest Creator',
      isGuest: true,
    );
    _currentUser = guest;
    await _saveSession(guest);
    return guest;
  }

  Future<void> signOut() async {
    _currentUser = null;
    try {
      final file = await _sessionFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
