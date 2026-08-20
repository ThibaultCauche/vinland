import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/vinland_user.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  List<VinlandUser> _users = [];
  bool _loaded = false;

  List<VinlandUser> get users => List.unmodifiable(_users);
  List<VinlandUser> get pendingUsers =>
      _users.where((u) => u.status == UserStatus.pending).toList();
  List<VinlandUser> get approvedUsers =>
      _users.where((u) => u.status == UserStatus.approved).toList();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _load();
    _loaded = true;
  }

  Future<String> _getFilePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'users.json');
  }

  Future<void> _load() async {
    final path = await _getFilePath();
    final file = File(path);
    if (!await file.exists()) {
      _users = [];
      return;
    }
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      _users = data
          .map((e) => VinlandUser.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('ERREUR CHARGEMENT USERS: $e');
      _users = [];
    }
  }

  Future<void> _save() async {
    final path = await _getFilePath();
    final file = File(path);
    await file
        .writeAsString(jsonEncode(_users.map((u) => u.toJson()).toList()));
  }

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// Inscription : crée un compte en attente d'approbation
  Future<VinlandUser?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    await ensureLoaded();

    // Vérifie si l'email existe déjà
    if (_users.any((u) => u.email.toLowerCase() == email.toLowerCase())) {
      return null;
    }

    final isFirstUser = _users.isEmpty;

    final user = VinlandUser(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim().toLowerCase(),
      passwordHash: _hashPassword(password),
      status: isFirstUser ? UserStatus.approved : UserStatus.pending,
      isAdmin: isFirstUser, // Le premier inscrit est admin
      createdAt: DateTime.now(),
    );

    _users.add(user);
    await _save();
    return user;
  }

  /// Connexion : retourne l'user si credentials OK et approuvé
  Future<VinlandUser?> login(String email, String password) async {
    await ensureLoaded();
    final hash = _hashPassword(password);
    final user = _users.firstWhere(
      (u) =>
          u.email.toLowerCase() == email.toLowerCase() &&
          u.passwordHash == hash,
      orElse: () => VinlandUser(
        id: '',
        firstName: '',
        lastName: '',
        email: '',
        passwordHash: '',
        createdAt: DateTime.now(),
      ),
    );
    if (user.id.isEmpty) return null;
    if (user.status != UserStatus.approved) return null;
    return user;
  }

  /// Approuver un utilisateur
  Future<bool> approveUser(String userId) async {
    await ensureLoaded();
    final index = _users.indexWhere((u) => u.id == userId);
    if (index == -1) return false;
    _users[index] = _users[index].copyWith(status: UserStatus.approved);
    await _save();
    return true;
  }

  /// Rejeter un utilisateur
  Future<bool> rejectUser(String userId) async {
    await ensureLoaded();
    final index = _users.indexWhere((u) => u.id == userId);
    if (index == -1) return false;
    _users[index] = _users[index].copyWith(status: UserStatus.rejected);
    await _save();
    return true;
  }

  /// Supprimer un utilisateur
  Future<bool> deleteUser(String userId) async {
    await ensureLoaded();
    _users.removeWhere((u) => u.id == userId);
    await _save();
    return true;
  }

  VinlandUser? getUserById(String id) {
    try {
      return _users.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  int get pendingCount =>
      _users.where((u) => u.status == UserStatus.pending).length;
}
