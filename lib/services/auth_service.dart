import 'package:shared_preferences/shared_preferences.dart';
import '../models/vinland_user.dart';
import 'user_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _userService = UserService();
  VinlandUser? _currentUser;

  VinlandUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  String? get userName => _currentUser?.fullName;
  String? get userEmail => _currentUser?.email;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  String? get userId => _currentUser?.id;

  static const _keyCurrentUserId = 'vinland_current_user_id';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyCurrentUserId);
    if (userId != null) {
      await _userService.ensureLoaded();
      _currentUser = _userService.getUserById(userId);
    }
  }

  Future<bool> login(String email, String password) async {
    final user = await _userService.login(email, password);
    if (user == null) return false;
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentUserId, user.id);
    return true;
  }

  Future<VinlandUser?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    return await _userService.register(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
    );
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentUserId);
  }
}
