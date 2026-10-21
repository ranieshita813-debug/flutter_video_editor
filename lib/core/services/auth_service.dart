import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/user_model.dart';

abstract class AuthRepository {
  UserModel? get currentUser;
  Future<UserModel?> loadSavedSession();
  Future<UserModel> signUp({
    required String email,
    required String password,
    required String displayName,
  });
  Future<UserModel> signIn({
    required String email,
    required String password,
  });
  Future<UserModel> signInAsGuest();
  Future<void> signOut();
}

class AuthService implements AuthRepository {
  AuthService();

  UserModel? _currentUser;
  final Map<String, String> _userCredentials = <String, String>{};
  final Map<String, UserModel> _usersByEmail = <String, UserModel>{};

  @override
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
    } catch (e, st) {
      AppLogger.warning('Failed to load local users DB', tag: 'AuthService', error: e, stackTrace: st);
    }
  }

  Future<void> _saveUsersDb() async {
    try {
      final file = await _dbFile;
      final data = <String, dynamic>{
        'users': _usersByEmail.map((k, v) => MapEntry(k, v.toJson())),
        'creds': _userCredentials,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e, st) {
      AppLogger.error('Failed to save local users DB', tag: 'AuthService', error: e, stackTrace: st);
    }
  }

  @override
  Future<UserModel?> loadSavedSession() async {
    await _loadUsersDb();

    try {
      final fbUser = fb.FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        _currentUser = UserModel(
          id: fbUser.uid,
          email: fbUser.email ?? 'user@motiongr.app',
          displayName: fbUser.displayName ?? 'User',
          isGuest: fbUser.isAnonymous,
        );
        return _currentUser;
      }
    } catch (e) {
      AppLogger.warning('Firebase auth check skipped: $e', tag: 'AuthService');
    }

    try {
      final file = await _sessionFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(json);
        return _currentUser;
      }
    } catch (e, st) {
      AppLogger.warning('Failed to load saved user session', tag: 'AuthService', error: e, stackTrace: st);
    }

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
    } catch (e, st) {
      AppLogger.error('Failed to save user session', tag: 'AuthService', error: e, stackTrace: st);
    }
  }

  @override
  Future<UserModel> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (email.trim().isEmpty || password.trim().isEmpty) {
      throw Exception('Email and password cannot be empty');
    }
    final normalizedEmail = email.trim().toLowerCase();
    final name = displayName.trim().isEmpty ? 'User' : displayName.trim();

    try {
      final cred = await fb.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      if (cred.user != null) {
        await cred.user!.updateDisplayName(name);
        final user = UserModel(
          id: cred.user!.uid,
          email: normalizedEmail,
          displayName: name,
          isGuest: false,
        );
        _currentUser = user;
        await _saveSession(user);
        return user;
      }
    } catch (e) {
      AppLogger.warning('Firebase signUp failed, falling back to local DB: $e', tag: 'AuthService');
    }

    await _loadUsersDb();
    if (_usersByEmail.containsKey(normalizedEmail)) {
      throw Exception('Account already exists for this email');
    }

    final user = UserModel(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      email: normalizedEmail,
      displayName: name,
      isGuest: false,
    );

    _userCredentials[normalizedEmail] = _hashPassword(password);
    _usersByEmail[normalizedEmail] = user;
    _currentUser = user;

    await _saveUsersDb();
    await _saveSession(user);
    return user;
  }

  @override
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final cred = await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      if (cred.user != null) {
        final user = UserModel(
          id: cred.user!.uid,
          email: normalizedEmail,
          displayName: cred.user!.displayName ?? normalizedEmail.split('@').first,
          isGuest: false,
        );
        _currentUser = user;
        await _saveSession(user);
        return user;
      }
    } catch (e) {
      AppLogger.warning('Firebase signIn failed, falling back to local DB: $e', tag: 'AuthService');
    }

    await _loadUsersDb();
    if (!_usersByEmail.containsKey(normalizedEmail)) {
      return signUp(
        email: email,
        password: password,
        displayName: normalizedEmail.split('@').first,
      );
    }

    final hashedInput = _hashPassword(password);
    if (_userCredentials[normalizedEmail] != hashedInput && _userCredentials[normalizedEmail] != password) {
      throw Exception('Invalid email or password');
    }

    final user = _usersByEmail[normalizedEmail]!;
    _currentUser = user;
    await _saveSession(user);
    return user;
  }

  @override
  Future<UserModel> signInAsGuest() async {
    try {
      final cred = await fb.FirebaseAuth.instance.signInAnonymously();
      if (cred.user != null) {
        final guest = UserModel(
          id: cred.user!.uid,
          email: 'guest@motiongr.app',
          displayName: 'Guest Creator',
          isGuest: true,
        );
        _currentUser = guest;
        await _saveSession(guest);
        return guest;
      }
    } catch (e) {
      AppLogger.warning('Firebase anonymous auth failed, using local guest session: $e', tag: 'AuthService');
    }

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

  String _hashPassword(String pass) {
    return sha256.convert(utf8.encode(pass)).toString();
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    try {
      await fb.FirebaseAuth.instance.signOut();
    } catch (e) {
      AppLogger.warning('Firebase signOut failed: $e', tag: 'AuthService');
    }
    try {
      final file = await _sessionFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, st) {
      AppLogger.warning('Failed to delete session file on sign out', tag: 'AuthService', error: e, stackTrace: st);
    }
  }
}
